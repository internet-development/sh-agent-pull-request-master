// NOTE(angeldev)
// Transaction support for atomic edit operations.
// Provides rollback capability when any edit fails in atomic mode.

use crate::edits::Edit;
use crate::error::{ApplyResult, EditOutcome};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

// NOTE(angeldev)
// Manages atomic batch processing with automatic rollback on failure.
// Backs up files before modification and restores them if any edit fails.
pub struct EditTransaction {
    workdir: PathBuf,
    backups: HashMap<PathBuf, Option<String>>, // None means file didn't exist (was created)
    applied_files: Vec<PathBuf>,
}

impl EditTransaction {
    // NOTE(angeldev)
    // Begins a new transaction in the given working directory.
    pub fn begin(workdir: &Path) -> Self {
        EditTransaction {
            workdir: workdir.to_path_buf(),
            backups: HashMap::new(),
            applied_files: Vec::new(),
        }
    }

    // NOTE(angeldev)
    // Backs up a file before modification.
    // Only backs up once per file (first modification wins).
    pub fn backup_file(&mut self, rel_path: &str) {
        let full_path = self.workdir.join(rel_path);

        // Only backup if we haven't already
        if self.backups.contains_key(&full_path) {
            return;
        }

        // Read current content (None if file doesn't exist)
        let content = std::fs::read_to_string(&full_path).ok();
        self.backups.insert(full_path.clone(), content);
        self.applied_files.push(full_path);
    }

    // NOTE(angeldev)
    // Applies a single edit within the transaction.
    // Returns the outcome but does NOT write to disk in dry-run mode.
    pub fn apply_edit(&mut self, edit: &Edit, index: usize, dry_run: bool) -> EditOutcome {
        let path = edit.path();

        // Backup before any modification
        if !dry_run {
            self.backup_file(path);
        }

        if dry_run {
            // In dry-run mode, simulate the edit without writing
            self.simulate_edit(edit, index)
        } else {
            // Actually apply the edit
            edit.apply(&self.workdir, index)
        }
    }

    // NOTE(angeldev)
    // Simulates an edit without writing to disk.
    // Returns Ok if the edit WOULD succeed, Error if it would fail.
    fn simulate_edit(&self, edit: &Edit, index: usize) -> EditOutcome {
        use crate::edits::{read_file, Edit::*};
        use crate::error::EditError;
        use crate::matcher::{count_occurrences, find_closest_matches, find_line_with_anchor, find_with_normalization, FindResult};

        let path = edit.path();
        let edit_type = edit.type_name();

        match edit {
            Replace { search, .. } | ReplaceAll { search, .. } => {
                match read_file(&self.workdir, path) {
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
                            // Try normalized matching
                            match find_with_normalization(&content, search) {
                                FindResult::NormalizedMatch { line_number, .. } => {
                                    EditOutcome::ok_with_details(
                                        index,
                                        path,
                                        edit_type,
                                        None,
                                        Some(format!("Would replace with indentation adjustment at line {} (dry-run)", line_number)),
                                    )
                                }
                                _ => {
                                    let closest = find_closest_matches(&content, search, 0.5, 3);
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

            InsertAfter { anchor, .. } | InsertBefore { anchor, .. } => {
                match read_file(&self.workdir, path) {
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
                            let closest = find_closest_matches(&content, anchor, 0.5, 3);
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

            InsertAtLine { line, .. } => {
                match read_file(&self.workdir, path) {
                    Ok(content) => {
                        let total_lines = content.lines().count();
                        if *line > 0 && *line <= total_lines + 1 {
                            EditOutcome::ok_with_details(
                                index,
                                path,
                                edit_type,
                                None,
                                Some(format!("Would insert at line {} (dry-run)", line)),
                            )
                        } else {
                            EditOutcome::from_error(
                                index,
                                path,
                                edit_type,
                                &EditError::LineOutOfRange {
                                    path: path.to_string(),
                                    line: *line,
                                    total_lines,
                                },
                            )
                        }
                    }
                    Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
                }
            }

            Create { .. } => {
                let full_path = self.workdir.join(path);
                if full_path.exists() {
                    EditOutcome::ok_with_details(
                        index,
                        path,
                        edit_type,
                        None,
                        Some("Would overwrite existing file (dry-run)".to_string()),
                    )
                } else {
                    EditOutcome::ok_with_details(
                        index,
                        path,
                        edit_type,
                        None,
                        Some("Would create new file (dry-run)".to_string()),
                    )
                }
            }

            DeleteFile { .. } => {
                let full_path = self.workdir.join(path);
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

            DeleteLines { start_line, end_line, .. } => {
                match read_file(&self.workdir, path) {
                    Ok(content) => {
                        let total_lines = content.lines().count();
                        if *start_line > 0 && *end_line >= *start_line && *end_line <= total_lines {
                            EditOutcome::ok_with_details(
                                index,
                                path,
                                edit_type,
                                None,
                                Some(format!("Would delete lines {}-{} (dry-run)", start_line, end_line)),
                            )
                        } else {
                            EditOutcome::from_error(
                                index,
                                path,
                                edit_type,
                                &EditError::InvalidLineRange {
                                    path: path.to_string(),
                                    start_line: *start_line,
                                    end_line: *end_line,
                                    total_lines,
                                },
                            )
                        }
                    }
                    Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
                }
            }

            DeleteMatch { search, .. } => {
                match read_file(&self.workdir, path) {
                    Ok(content) => {
                        let count = content.lines().filter(|l| l.contains(search)).count();
                        EditOutcome::ok_with_details(
                            index,
                            path,
                            edit_type,
                            None,
                            Some(format!("Would delete {} matching line(s) (dry-run)", count)),
                        )
                    }
                    Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
                }
            }

            Append { .. } | Prepend { .. } => {
                match read_file(&self.workdir, path) {
                    Ok(_) => EditOutcome::ok_with_details(
                        index,
                        path,
                        edit_type,
                        None,
                        Some("Would append/prepend content (dry-run)".to_string()),
                    ),
                    Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
                }
            }
        }
    }

    // NOTE(angeldev)
    // Rolls back all changes made during this transaction.
    // Restores files to their original state, deletes newly created files.
    pub fn rollback(self) {
        eprintln!("🔄 Rolling back {} file(s)...", self.backups.len());

        for (path, original_content) in self.backups {
            match original_content {
                Some(content) => {
                    // Restore original content
                    if let Err(e) = std::fs::write(&path, content) {
                        eprintln!("⚠️  Failed to restore {}: {}", path.display(), e);
                    } else {
                        eprintln!("   Restored: {}", path.display());
                    }
                }
                None => {
                    // File was newly created - delete it
                    if path.exists() {
                        if let Err(e) = std::fs::remove_file(&path) {
                            eprintln!("⚠️  Failed to remove {}: {}", path.display(), e);
                        } else {
                            eprintln!("   Removed: {}", path.display());
                        }
                    }
                }
            }
        }

        eprintln!("✓ Rollback complete");
    }

    // NOTE(angeldev)
    // Commits the transaction (no-op, just consumes self without rolling back).
    pub fn commit(self) {
        // Just drop self without rolling back
    }
}

// NOTE(angeldev)
// Applies edits with support for dry-run and partial/atomic modes.
pub fn apply_with_transaction(
    workdir: &Path,
    edits: &[Edit],
    dry_run: bool,
    partial: bool,
) -> ApplyResult {
    let mut result = ApplyResult::new();
    let mut transaction = EditTransaction::begin(workdir);

    for (index, edit) in edits.iter().enumerate() {
        let outcome = transaction.apply_edit(edit, index, dry_run);
        let is_success = outcome.is_success();

        result.add_outcome(outcome);

        // In atomic mode (not partial), fail fast and rollback
        if !is_success && !partial && !dry_run {
            eprintln!();
            eprintln!("❌ Edit {} failed - triggering rollback", index + 1);
            transaction.rollback();
            return result;
        }
    }

    if !dry_run {
        // All edits succeeded (or we're in partial mode) - commit
        transaction.commit();
    }

    result
}
