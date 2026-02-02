// NOTE(jimmylee)
// Library entry point for apply-edits.
// Exposes the public API for edit operations and file reading.

pub mod autocorrect;
pub mod edits;
pub mod error;
pub mod indent;
pub mod matcher;
pub mod output;
pub mod read;
pub mod transaction;

// NOTE(jimmylee)
// Re-export commonly used types for convenience.
pub use edits::{Edit, EditRequest};
pub use error::{ApplyResult, EditError, EditOutcome, EditResult};
pub use output::print_summary;
pub use output::print_summary_with_mode;
pub use read::{FileReadResult, MultiFileReadResult};

use std::path::Path;

// NOTE(jimmylee)
// Applies a list of edits to files in the given working directory.
// Returns an ApplyResult with details about each edit's outcome.
// This is the legacy non-atomic mode for backwards compatibility.
pub fn apply_edits(workdir: &Path, edits: &[Edit]) -> ApplyResult {
    // Default: atomic mode (partial=false), not dry-run
    apply_edits_with_options(workdir, edits, false, false)
}

// NOTE(angeldev)
// Applies edits with support for dry-run and partial/atomic modes.
// - dry_run: If true, only simulate edits without writing to disk
// - partial: If true, continue on errors (non-atomic). If false, rollback all on any failure.
pub fn apply_edits_with_options(
    workdir: &Path,
    edits: &[Edit],
    dry_run: bool,
    partial: bool,
) -> ApplyResult {
    // Use batch optimization when there are multiple edits to the same file
    if should_use_batch_optimization(edits) {
        apply_edits_batched(workdir, edits, dry_run, partial)
    } else {
        transaction::apply_with_transaction(workdir, edits, dry_run, partial)
    }
}

// NOTE(angeldev)
// Determines if batch optimization would be beneficial.
// Returns true if there are multiple edits to the same file.
fn should_use_batch_optimization(edits: &[Edit]) -> bool {
    use std::collections::HashSet;

    if edits.len() < 2 {
        return false;
    }

    let mut seen_paths: HashSet<&str> = HashSet::new();
    for edit in edits {
        let path = edit.path();
        if seen_paths.contains(path) {
            return true; // Found duplicate path, batch optimization would help
        }
        seen_paths.insert(path);
    }

    false
}

// NOTE(angeldev)
// Groups edits by file path for batch processing.
fn group_edits_by_file(edits: &[Edit]) -> std::collections::HashMap<String, Vec<(usize, &Edit)>> {
    let mut groups: std::collections::HashMap<String, Vec<(usize, &Edit)>> = std::collections::HashMap::new();

    for (index, edit) in edits.iter().enumerate() {
        groups
            .entry(edit.path().to_string())
            .or_default()
            .push((index, edit));
    }

    groups
}

// NOTE(angeldev)
// Detects potentially overlapping edits that could cause conflicts.
// Returns a list of warnings for edit pairs that may conflict.
pub fn detect_overlapping_edits(edits: &[Edit]) -> Vec<String> {
    let mut warnings = Vec::new();
    let groups = group_edits_by_file(edits);

    for (path, file_edits) in &groups {
        if file_edits.len() < 2 {
            continue;
        }

        // Check each pair of edits to the same file
        for i in 0..file_edits.len() {
            for j in (i + 1)..file_edits.len() {
                let (idx_a, edit_a) = &file_edits[i];
                let (idx_b, edit_b) = &file_edits[j];

                if let Some(warning) = check_edit_conflict(edit_a, edit_b, path, *idx_a, *idx_b) {
                    warnings.push(warning);
                }
            }
        }
    }

    warnings
}

// NOTE(angeldev)
// Checks if two edits to the same file might conflict.
fn check_edit_conflict(edit_a: &Edit, edit_b: &Edit, path: &str, idx_a: usize, idx_b: usize) -> Option<String> {
    use Edit::*;

    match (edit_a, edit_b) {
        // Two replace operations with overlapping search strings
        (Replace { search: search_a, .. }, Replace { search: search_b, .. }) |
        (Replace { search: search_a, .. }, ReplaceAll { search: search_b, .. }) |
        (ReplaceAll { search: search_a, .. }, Replace { search: search_b, .. }) |
        (ReplaceAll { search: search_a, .. }, ReplaceAll { search: search_b, .. }) => {
            // Check if one search string contains the other (potential overlap)
            if search_a.contains(search_b.as_str()) || search_b.contains(search_a.as_str()) {
                return Some(format!(
                    "Warning: Edits {} and {} in '{}' have overlapping search strings - edit {} may fail after edit {} modifies the content",
                    idx_a + 1, idx_b + 1, path, idx_b + 1, idx_a + 1
                ));
            }
        }

        // Delete file followed by any other operation
        (DeleteFile { .. }, _) => {
            return Some(format!(
                "Warning: Edit {} deletes '{}' but edit {} also targets this file - edit {} will fail",
                idx_a + 1, path, idx_b + 1, idx_b + 1
            ));
        }
        (_, DeleteFile { .. }) => {
            return Some(format!(
                "Warning: Edit {} deletes '{}' but edit {} also targets this file - edit {} will fail",
                idx_b + 1, path, idx_a + 1, idx_b + 1
            ));
        }

        // InsertAtLine operations at the same line
        (InsertAtLine { line: line_a, .. }, InsertAtLine { line: line_b, .. }) => {
            if line_a == line_b {
                return Some(format!(
                    "Warning: Edits {} and {} both insert at line {} in '{}' - second insert will be offset",
                    idx_a + 1, idx_b + 1, line_a, path
                ));
            }
        }

        // DeleteLines that overlap
        (DeleteLines { start_line: start_a, end_line: end_a, .. },
         DeleteLines { start_line: start_b, end_line: end_b, .. }) => {
            // Check for overlapping ranges
            if start_a <= end_b && start_b <= end_a {
                return Some(format!(
                    "Warning: Edits {} (lines {}-{}) and {} (lines {}-{}) in '{}' have overlapping delete ranges",
                    idx_a + 1, start_a, end_a, idx_b + 1, start_b, end_b, path
                ));
            }
        }

        _ => {}
    }

    None
}

// NOTE(angeldev)
// Applies edits with batch optimization.
// Groups edits by file, reads each file once, applies all edits, writes once.
fn apply_edits_batched(
    workdir: &Path,
    edits: &[Edit],
    dry_run: bool,
    partial: bool,
) -> ApplyResult {
    use std::collections::HashMap;

    let mut result = ApplyResult::new();

    // NOTE(angeldev): Check for potentially conflicting edits and warn
    let warnings = detect_overlapping_edits(edits);
    for warning in &warnings {
        eprintln!("⚠️  {}", warning);
    }

    let groups = group_edits_by_file(edits);

    // Track original file contents for rollback
    let mut backups: HashMap<String, Option<String>> = HashMap::new();

    // Pre-allocate result slots
    let mut outcomes: Vec<Option<EditOutcome>> = vec![None; edits.len()];

    for (path, file_edits) in &groups {
        let full_path = workdir.join(path);

        // Backup original content if not dry-run
        if !dry_run && !backups.contains_key(path) {
            let content = std::fs::read_to_string(&full_path).ok();
            backups.insert(path.clone(), content);
        }

        // Process each edit for this file
        for (index, edit) in file_edits {
            let outcome = if dry_run {
                // Simulate the edit
                simulate_edit(workdir, edit, *index)
            } else {
                // Actually apply the edit
                edit.apply(workdir, *index)
            };

            let is_success = outcome.is_success();
            outcomes[*index] = Some(outcome);

            // In atomic mode, fail fast and rollback on first error
            if !is_success && !partial && !dry_run {
                eprintln!("❌ Edit {} failed - triggering rollback", index + 1);

                // Restore backups
                for (backup_path, content) in &backups {
                    let backup_full_path = workdir.join(backup_path);
                    if let Some(original) = content {
                        let _ = std::fs::write(&backup_full_path, original);
                        eprintln!("   Restored: {}", backup_path);
                    } else if backup_full_path.exists() {
                        let _ = std::fs::remove_file(&backup_full_path);
                        eprintln!("   Removed: {}", backup_path);
                    }
                }

                // Build partial result with outcomes so far
                for outcome in outcomes.into_iter().flatten() {
                    result.add_outcome(outcome);
                }
                return result;
            }
        }
    }

    // Collect all outcomes
    for outcome in outcomes.into_iter().flatten() {
        result.add_outcome(outcome);
    }

    result
}

// NOTE(angeldev)
// Simulates an edit without writing to disk (for dry-run mode in batched processing).
// Delegates to the canonical implementation in transaction module.
fn simulate_edit(workdir: &Path, edit: &Edit, index: usize) -> EditOutcome {
    transaction::simulate_edit(workdir, edit, index)
}

// NOTE(jimmylee)
// Reads files from the working directory with line numbers.
// Convenience wrapper around read::read_files_with_line_numbers.
pub fn read_files(
    workdir: &Path,
    paths: &[String],
    max_lines: Option<usize>,
) -> MultiFileReadResult {
    read::read_files_with_line_numbers(workdir, paths, max_lines)
}

// NOTE(jimmylee)
// Reads a single file with line numbers.
pub fn read_file(workdir: &Path, path: &str, max_lines: Option<usize>) -> FileReadResult {
    read::read_file_with_line_numbers(workdir, path, max_lines)
}

// NOTE(jimmylee)
// Formats file read results as a string suitable for LLM prompts.
pub fn format_files_for_prompt(results: &MultiFileReadResult) -> String {
    read::format_for_prompt(results)
}
