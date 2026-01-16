// NOTE(jimmylee)
// Error types for the apply-edits tool.
// Uses thiserror for ergonomic error handling and display formatting.

use serde::Serialize;
use thiserror::Error;

// NOTE(jimmylee)
// Main error type for edit operations.
// Each variant includes context needed for helpful error messages.
#[derive(Error, Debug)]
pub enum EditError {
    #[error("File not found: {path}")]
    FileNotFound { path: String },

    #[error("Search string not found in file: {path}")]
    SearchNotFound {
        path: String,
        search_preview: String,
        closest_matches: Vec<ClosestMatch>,
    },

    #[error("Anchor string not found in file: {path}")]
    AnchorNotFound {
        path: String,
        anchor_preview: String,
        closest_matches: Vec<ClosestMatch>,
    },

    #[error("Line {line} out of range (file has {total_lines} lines): {path}")]
    LineOutOfRange {
        path: String,
        line: usize,
        total_lines: usize,
    },

    #[error("Invalid line range {start_line}-{end_line} (file has {total_lines} lines): {path}")]
    InvalidLineRange {
        path: String,
        start_line: usize,
        end_line: usize,
        total_lines: usize,
    },

    #[error("Failed to read file: {path} - {reason}")]
    ReadError { path: String, reason: String },

    #[error("Failed to write file: {path} - {reason}")]
    WriteError { path: String, reason: String },

    #[error("Failed to create directory: {path} - {reason}")]
    DirectoryError { path: String, reason: String },

    #[error("Failed to delete file: {path} - {reason}")]
    DeleteError { path: String, reason: String },

    #[error("Multiple matches found ({count}) - search string is not unique: {path}")]
    MultipleMatches {
        path: String,
        count: usize,
        search_preview: String,
    },

    #[error("Invalid edit: {reason}")]
    InvalidEdit { reason: String },
}

// NOTE(jimmylee)
// Represents a close match found during fuzzy searching.
// Used to provide helpful suggestions when exact match fails.
#[derive(Debug, Clone, Serialize)]
pub struct ClosestMatch {
    pub line: usize,
    pub similarity: f64,
    pub content: String,
    pub context_before: Vec<String>,
    pub context_after: Vec<String>,
}

// NOTE(jimmylee)
// Result type alias for edit operations.
pub type EditResult<T> = Result<T, EditError>;

// NOTE(jimmylee)
// Represents the outcome of a single edit operation.
// Used for structured JSON output.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status")]
pub enum EditOutcome {
    #[serde(rename = "ok")]
    Ok {
        index: usize,
        path: String,
        #[serde(rename = "type")]
        edit_type: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        lines_affected: Option<Vec<usize>>,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    #[serde(rename = "error")]
    Error {
        index: usize,
        path: String,
        #[serde(rename = "type")]
        edit_type: String,
        error: String,
        message: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        search_preview: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        closest_matches: Option<Vec<ClosestMatch>>,
        #[serde(skip_serializing_if = "Option::is_none")]
        hint: Option<String>,
    },
    #[serde(rename = "warning")]
    Warning {
        index: usize,
        path: String,
        #[serde(rename = "type")]
        edit_type: String,
        warning: String,
        message: String,
    },
}

impl EditOutcome {
    // NOTE(jimmylee)
    // Creates a successful outcome for an edit operation.
    pub fn ok(index: usize, path: &str, edit_type: &str) -> Self {
        EditOutcome::Ok {
            index,
            path: path.to_string(),
            edit_type: edit_type.to_string(),
            lines_affected: None,
            message: None,
        }
    }

    // NOTE(jimmylee)
    // Creates a successful outcome with additional details.
    pub fn ok_with_details(
        index: usize,
        path: &str,
        edit_type: &str,
        lines_affected: Option<Vec<usize>>,
        message: Option<String>,
    ) -> Self {
        EditOutcome::Ok {
            index,
            path: path.to_string(),
            edit_type: edit_type.to_string(),
            lines_affected,
            message,
        }
    }

    // NOTE(jimmylee)
    // Creates an error outcome from an EditError.
    pub fn from_error(index: usize, path: &str, edit_type: &str, error: &EditError) -> Self {
        match error {
            EditError::SearchNotFound {
                search_preview,
                closest_matches,
                ..
            } => EditOutcome::Error {
                index,
                path: path.to_string(),
                edit_type: edit_type.to_string(),
                error: "search_not_found".to_string(),
                message: error.to_string(),
                search_preview: Some(search_preview.clone()),
                closest_matches: Some(closest_matches.clone()),
                hint: Some(generate_hint_for_search_not_found(closest_matches)),
            },
            EditError::AnchorNotFound {
                anchor_preview,
                closest_matches,
                ..
            } => EditOutcome::Error {
                index,
                path: path.to_string(),
                edit_type: edit_type.to_string(),
                error: "anchor_not_found".to_string(),
                message: error.to_string(),
                search_preview: Some(anchor_preview.clone()),
                closest_matches: Some(closest_matches.clone()),
                hint: Some(generate_hint_for_search_not_found(closest_matches)),
            },
            _ => EditOutcome::Error {
                index,
                path: path.to_string(),
                edit_type: edit_type.to_string(),
                error: error_code(error),
                message: error.to_string(),
                search_preview: None,
                closest_matches: None,
                hint: None,
            },
        }
    }

    // NOTE(jimmylee)
    // Creates a warning outcome (edit succeeded but with caveats).
    pub fn warning(index: usize, path: &str, edit_type: &str, warning: &str, message: &str) -> Self {
        EditOutcome::Warning {
            index,
            path: path.to_string(),
            edit_type: edit_type.to_string(),
            warning: warning.to_string(),
            message: message.to_string(),
        }
    }

    // NOTE(jimmylee)
    // Returns true if this outcome represents a successful edit.
    pub fn is_success(&self) -> bool {
        matches!(self, EditOutcome::Ok { .. } | EditOutcome::Warning { .. })
    }
}

// NOTE(jimmylee)
// Generates a machine-readable error code from an EditError.
fn error_code(error: &EditError) -> String {
    match error {
        EditError::FileNotFound { .. } => "file_not_found",
        EditError::SearchNotFound { .. } => "search_not_found",
        EditError::AnchorNotFound { .. } => "anchor_not_found",
        EditError::LineOutOfRange { .. } => "line_out_of_range",
        EditError::InvalidLineRange { .. } => "invalid_line_range",
        EditError::ReadError { .. } => "read_error",
        EditError::WriteError { .. } => "write_error",
        EditError::DirectoryError { .. } => "directory_error",
        EditError::DeleteError { .. } => "delete_error",
        EditError::MultipleMatches { .. } => "multiple_matches",
        EditError::InvalidEdit { .. } => "invalid_edit",
    }
    .to_string()
}

// NOTE(jimmylee)
// Generates a helpful hint based on closest matches found.
fn generate_hint_for_search_not_found(closest_matches: &[ClosestMatch]) -> String {
    if closest_matches.is_empty() {
        return "No similar content found. The file may have changed significantly.".to_string();
    }

    let best_match = &closest_matches[0];
    if best_match.similarity > 0.9 {
        format!(
            "Very close match at line {}. Check for minor differences (whitespace, punctuation).",
            best_match.line
        )
    } else if best_match.similarity > 0.7 {
        format!(
            "Similar content found at line {}. The code may have been modified.",
            best_match.line
        )
    } else {
        format!(
            "Partial match at line {} ({}% similar). The code structure may have changed.",
            best_match.line,
            (best_match.similarity * 100.0) as u32
        )
    }
}

// NOTE(jimmylee)
// Overall result of applying all edits.
#[derive(Debug, Serialize)]
pub struct ApplyResult {
    pub success: bool,
    pub applied: usize,
    pub failed: usize,
    pub edits: Vec<EditOutcome>,
}

impl ApplyResult {
    pub fn new() -> Self {
        ApplyResult {
            success: true,
            applied: 0,
            failed: 0,
            edits: Vec::new(),
        }
    }

    pub fn add_outcome(&mut self, outcome: EditOutcome) {
        if outcome.is_success() {
            self.applied += 1;
        } else {
            self.failed += 1;
            self.success = false;
        }
        self.edits.push(outcome);
    }
}

impl Default for ApplyResult {
    fn default() -> Self {
        Self::new()
    }
}
