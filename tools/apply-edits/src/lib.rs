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
fn simulate_edit(workdir: &Path, edit: &Edit, index: usize) -> EditOutcome {
    use crate::edits::read_file;
    use crate::matcher::{count_occurrences, find_line_with_anchor, find_with_normalization, FindResult};

    let path = edit.path();
    let edit_type = edit.type_name();

    match edit {
        Edit::Replace { search, .. } | Edit::ReplaceAll { search, .. } => {
            match read_file(workdir, path) {
                Ok(content) => {
                    let count = count_occurrences(&content, search);
                    if count > 0 {
                        EditOutcome::ok_with_details(
                            index,
                            path,
                            edit_type,
                            None,
                            Some(format!("Would replace {} occurrence(s) (dry-run)", count)),
                        )
                    } else {
                        match find_with_normalization(&content, search) {
                            FindResult::NormalizedMatch { line_number, .. } => {
                                EditOutcome::ok_with_details(
                                    index,
                                    path,
                                    edit_type,
                                    None,
                                    Some(format!("Would replace with indent adjust at line {} (dry-run)", line_number)),
                                )
                            }
                            _ => {
                                let closest = crate::matcher::find_closest_matches(&content, search, 0.5, 3);
                                EditOutcome::from_error(
                                    index,
                                    path,
                                    edit_type,
                                    &EditError::SearchNotFound {
                                        path: path.to_string(),
                                        search_preview: search.chars().take(200).collect(),
                                        closest_matches: closest,
                                    },
                                )
                            }
                        }
                    }
                }
                Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
            }
        }

        Edit::InsertAfter { anchor, .. } | Edit::InsertBefore { anchor, .. } => {
            match read_file(workdir, path) {
                Ok(content) => {
                    if find_line_with_anchor(&content, anchor).is_some() {
                        EditOutcome::ok_with_details(
                            index,
                            path,
                            edit_type,
                            None,
                            Some("Would insert content (dry-run)".to_string()),
                        )
                    } else {
                        let closest = crate::matcher::find_closest_matches(&content, anchor, 0.5, 3);
                        EditOutcome::from_error(
                            index,
                            path,
                            edit_type,
                            &EditError::AnchorNotFound {
                                path: path.to_string(),
                                anchor_preview: anchor.chars().take(200).collect(),
                                closest_matches: closest,
                            },
                        )
                    }
                }
                Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
            }
        }

        Edit::Create { .. } => {
            let full_path = workdir.join(path);
            if full_path.exists() {
                EditOutcome::ok_with_details(
                    index,
                    path,
                    edit_type,
                    None,
                    Some("Would overwrite file (dry-run)".to_string()),
                )
            } else {
                EditOutcome::ok_with_details(
                    index,
                    path,
                    edit_type,
                    None,
                    Some("Would create file (dry-run)".to_string()),
                )
            }
        }

        Edit::DeleteFile { .. } => {
            let full_path = workdir.join(path);
            if full_path.exists() {
                EditOutcome::ok_with_details(
                    index,
                    path,
                    edit_type,
                    None,
                    Some("Would delete file (dry-run)".to_string()),
                )
            } else {
                EditOutcome::from_error(
                    index,
                    path,
                    edit_type,
                    &EditError::FileNotFound {
                        path: path.to_string(),
                    },
                )
            }
        }

        _ => {
            // For other edit types, assume success in dry-run
            EditOutcome::ok_with_details(
                index,
                path,
                edit_type,
                None,
                Some(format!("Would apply {} (dry-run)", edit_type)),
            )
        }
    }
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
