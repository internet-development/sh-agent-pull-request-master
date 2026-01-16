// NOTE(jimmylee)
// Edit operations module.
// Defines the Edit enum and provides apply functions for each edit type.

pub mod delete;
pub mod file_ops;
pub mod insert;
pub mod replace;

use crate::error::{EditError, EditOutcome, EditResult};
use serde::Deserialize;
use std::path::Path;

// NOTE(jimmylee)
// Represents a single edit operation.
// Uses serde's tag attribute to deserialize based on the "type" field.
#[derive(Debug, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Edit {
    // Replace first occurrence of search with replace
    Replace {
        path: String,
        search: String,
        replace: String,
    },
    // Replace all occurrences of search with replace
    ReplaceAll {
        path: String,
        search: String,
        replace: String,
    },
    // Insert content after line containing anchor
    // NOTE(angeldev): Accepts "anchor", "search", "match", "after", "pattern", "at", or "location" as field name
    InsertAfter {
        path: String,
        #[serde(alias = "search", alias = "match", alias = "after", alias = "pattern", alias = "at", alias = "location")]
        anchor: String,
        content: String,
    },
    // Insert content before line containing anchor
    // NOTE(angeldev): Accepts "anchor", "search", "match", "before", "pattern", "at", or "location" as field name
    InsertBefore {
        path: String,
        #[serde(alias = "search", alias = "match", alias = "before", alias = "pattern", alias = "at", alias = "location")]
        anchor: String,
        content: String,
    },
    // Insert content at specific line number (1-indexed)
    InsertAtLine {
        path: String,
        line: usize,
        content: String,
    },
    // Create a new file with content
    Create { path: String, content: String },
    // Delete a file
    DeleteFile { path: String },
    // Delete lines from start_line to end_line (1-indexed, inclusive)
    DeleteLines {
        path: String,
        start_line: usize,
        end_line: usize,
    },
    // Delete all lines containing search string
    DeleteMatch { path: String, search: String },
    // Append content to end of file
    Append { path: String, content: String },
    // Prepend content to beginning of file
    Prepend { path: String, content: String },
}

impl Edit {
    // NOTE(jimmylee)
    // Returns the path affected by this edit.
    pub fn path(&self) -> &str {
        match self {
            Edit::Replace { path, .. } => path,
            Edit::ReplaceAll { path, .. } => path,
            Edit::InsertAfter { path, .. } => path,
            Edit::InsertBefore { path, .. } => path,
            Edit::InsertAtLine { path, .. } => path,
            Edit::Create { path, .. } => path,
            Edit::DeleteFile { path } => path,
            Edit::DeleteLines { path, .. } => path,
            Edit::DeleteMatch { path, .. } => path,
            Edit::Append { path, .. } => path,
            Edit::Prepend { path, .. } => path,
        }
    }

    // NOTE(jimmylee)
    // Returns the edit type as a string for logging/output.
    pub fn type_name(&self) -> &'static str {
        match self {
            Edit::Replace { .. } => "replace",
            Edit::ReplaceAll { .. } => "replace_all",
            Edit::InsertAfter { .. } => "insert_after",
            Edit::InsertBefore { .. } => "insert_before",
            Edit::InsertAtLine { .. } => "insert_at_line",
            Edit::Create { .. } => "create",
            Edit::DeleteFile { .. } => "delete_file",
            Edit::DeleteLines { .. } => "delete_lines",
            Edit::DeleteMatch { .. } => "delete_match",
            Edit::Append { .. } => "append",
            Edit::Prepend { .. } => "prepend",
        }
    }

    // NOTE(jimmylee)
    // Applies this edit operation to the filesystem.
    // Returns an EditOutcome indicating success or failure.
    pub fn apply(&self, workdir: &Path, index: usize) -> EditOutcome {
        let path = self.path();
        let edit_type = self.type_name();

        match self.apply_inner(workdir) {
            Ok(message) => EditOutcome::ok_with_details(index, path, edit_type, None, Some(message)),
            Err(e) => EditOutcome::from_error(index, path, edit_type, &e),
        }
    }

    // NOTE(jimmylee)
    // Internal apply function that returns Result for easier error handling.
    fn apply_inner(&self, workdir: &Path) -> EditResult<String> {
        match self {
            Edit::Replace {
                path,
                search,
                replace,
            } => replace::apply_replace(workdir, path, search, replace),

            Edit::ReplaceAll {
                path,
                search,
                replace,
            } => replace::apply_replace_all(workdir, path, search, replace),

            Edit::InsertAfter {
                path,
                anchor,
                content,
            } => insert::apply_insert_after(workdir, path, anchor, content),

            Edit::InsertBefore {
                path,
                anchor,
                content,
            } => insert::apply_insert_before(workdir, path, anchor, content),

            Edit::InsertAtLine {
                path,
                line,
                content,
            } => insert::apply_insert_at_line(workdir, path, *line, content),

            Edit::Create { path, content } => file_ops::apply_create(workdir, path, content),

            Edit::DeleteFile { path } => delete::apply_delete_file(workdir, path),

            Edit::DeleteLines {
                path,
                start_line,
                end_line,
            } => delete::apply_delete_lines(workdir, path, *start_line, *end_line),

            Edit::DeleteMatch { path, search } => delete::apply_delete_match(workdir, path, search),

            Edit::Append { path, content } => file_ops::apply_append(workdir, path, content),

            Edit::Prepend { path, content } => file_ops::apply_prepend(workdir, path, content),
        }
    }
}

// NOTE(jimmylee)
// Request structure for apply command JSON input.
#[derive(Debug, Deserialize)]
pub struct EditRequest {
    pub edits: Vec<Edit>,
    #[serde(default)]
    pub commit_message: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
}

// NOTE(angeldev)
// Default threshold for large file handling (100KB)
pub const LARGE_FILE_THRESHOLD: u64 = 100 * 1024;

// NOTE(angeldev)
// Checks if a file is considered "large" (over threshold).
pub fn is_large_file(workdir: &Path, path: &str) -> bool {
    let file_path = workdir.join(path);
    if let Ok(metadata) = std::fs::metadata(&file_path) {
        metadata.len() > LARGE_FILE_THRESHOLD
    } else {
        false
    }
}

// NOTE(jimmylee)
// Helper function to read file content, returning appropriate error.
// NOTE(angeldev): Uses memory-mapped I/O for large files (>100KB) to reduce memory pressure.
pub fn read_file(workdir: &Path, path: &str) -> EditResult<String> {
    let file_path = workdir.join(path);

    if !file_path.exists() {
        return Err(EditError::FileNotFound {
            path: path.to_string(),
        });
    }

    // Check file size to decide on reading strategy
    let metadata = std::fs::metadata(&file_path).map_err(|e| EditError::ReadError {
        path: path.to_string(),
        reason: e.to_string(),
    })?;

    if metadata.len() > LARGE_FILE_THRESHOLD {
        // Use memory-mapped I/O for large files
        read_file_mmap(workdir, path)
    } else {
        // Standard read for smaller files
        std::fs::read_to_string(&file_path).map_err(|e| EditError::ReadError {
            path: path.to_string(),
            reason: e.to_string(),
        })
    }
}

// NOTE(angeldev)
// Reads a large file using memory-mapped I/O.
// More memory-efficient for files over 100KB as it doesn't load the entire file into memory at once.
fn read_file_mmap(workdir: &Path, path: &str) -> EditResult<String> {
    use memmap2::Mmap;
    use std::fs::File;

    let file_path = workdir.join(path);

    let file = File::open(&file_path).map_err(|e| EditError::ReadError {
        path: path.to_string(),
        reason: e.to_string(),
    })?;

    // SAFETY: We're only reading, and the file won't change during our operation
    // In a production system with concurrent access, this would need more care
    let mmap = unsafe {
        Mmap::map(&file).map_err(|e| EditError::ReadError {
            path: path.to_string(),
            reason: format!("Failed to memory-map file: {}", e),
        })?
    };

    // Convert to string
    std::str::from_utf8(&mmap)
        .map(|s| s.to_string())
        .map_err(|e| EditError::ReadError {
            path: path.to_string(),
            reason: format!("File is not valid UTF-8: {}", e),
        })
}

// NOTE(jimmylee)
// Helper function to write file content, returning appropriate error.
pub fn write_file(workdir: &Path, path: &str, content: &str) -> EditResult<()> {
    let file_path = workdir.join(path);

    std::fs::write(&file_path, content).map_err(|e| EditError::WriteError {
        path: path.to_string(),
        reason: e.to_string(),
    })
}
