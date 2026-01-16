// NOTE(jimmylee)
// Insert edit operations.
// Handles insert_after, insert_before, and insert_at_line.

use crate::edits::{read_file, write_file};
use crate::error::{EditError, EditResult};
use crate::matcher::{
    find_closest_matches, insert_after_line, insert_at_line, insert_before_line, truncate_preview,
};
use std::path::Path;

// NOTE(jimmylee)
// Similarity threshold for finding closest matches when anchor fails.
const SIMILARITY_THRESHOLD: f64 = 0.5;

// NOTE(jimmylee)
// Maximum number of closest matches to return in error messages.
const MAX_CLOSEST_MATCHES: usize = 3;

// NOTE(jimmylee)
// Applies an insert_after operation.
// Inserts content after the first line containing the anchor string.
pub fn apply_insert_after(
    workdir: &Path,
    path: &str,
    anchor: &str,
    content: &str,
) -> EditResult<String> {
    let file_content = read_file(workdir, path)?;

    // Validate anchor is not empty
    if anchor.is_empty() {
        return Err(EditError::InvalidEdit {
            reason: "Anchor string cannot be empty".to_string(),
        });
    }

    // Try to insert after anchor
    match insert_after_line(&file_content, anchor, content) {
        Some((new_content, line)) => {
            write_file(workdir, path, &new_content)?;
            Ok(format!("Inserted after anchor at line {}", line - 1))
        }
        None => {
            // Anchor not found - find closest matches
            let closest =
                find_closest_matches(&file_content, anchor, SIMILARITY_THRESHOLD, MAX_CLOSEST_MATCHES);

            Err(EditError::AnchorNotFound {
                path: path.to_string(),
                anchor_preview: truncate_preview(anchor, 200),
                closest_matches: closest,
            })
        }
    }
}

// NOTE(jimmylee)
// Applies an insert_before operation.
// Inserts content before the first line containing the anchor string.
pub fn apply_insert_before(
    workdir: &Path,
    path: &str,
    anchor: &str,
    content: &str,
) -> EditResult<String> {
    let file_content = read_file(workdir, path)?;

    // Validate anchor is not empty
    if anchor.is_empty() {
        return Err(EditError::InvalidEdit {
            reason: "Anchor string cannot be empty".to_string(),
        });
    }

    // Try to insert before anchor
    match insert_before_line(&file_content, anchor, content) {
        Some((new_content, line)) => {
            write_file(workdir, path, &new_content)?;
            Ok(format!("Inserted before anchor at line {}", line))
        }
        None => {
            // Anchor not found - find closest matches
            let closest =
                find_closest_matches(&file_content, anchor, SIMILARITY_THRESHOLD, MAX_CLOSEST_MATCHES);

            Err(EditError::AnchorNotFound {
                path: path.to_string(),
                anchor_preview: truncate_preview(anchor, 200),
                closest_matches: closest,
            })
        }
    }
}

// NOTE(jimmylee)
// Applies an insert_at_line operation.
// Inserts content at the specified line number (1-indexed).
pub fn apply_insert_at_line(
    workdir: &Path,
    path: &str,
    line: usize,
    content: &str,
) -> EditResult<String> {
    let file_content = read_file(workdir, path)?;
    let total_lines = file_content.lines().count();

    // Validate line number
    if line == 0 {
        return Err(EditError::InvalidEdit {
            reason: "Line number must be >= 1".to_string(),
        });
    }

    if line > total_lines + 1 {
        return Err(EditError::LineOutOfRange {
            path: path.to_string(),
            line,
            total_lines,
        });
    }

    // Insert at line
    match insert_at_line(&file_content, line, content) {
        Some(new_content) => {
            write_file(workdir, path, &new_content)?;
            Ok(format!("Inserted at line {}", line))
        }
        None => Err(EditError::LineOutOfRange {
            path: path.to_string(),
            line,
            total_lines,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_insert_after() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\n").unwrap();

        let result = apply_insert_after(dir.path(), path, "line2", "inserted");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("line2\ninserted\nline3"));
    }

    #[test]
    fn test_insert_before() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\n").unwrap();

        let result = apply_insert_before(dir.path(), path, "line2", "inserted");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("line1\ninserted\nline2"));
    }

    #[test]
    fn test_insert_at_line() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\n").unwrap();

        let result = apply_insert_at_line(dir.path(), path, 2, "inserted");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("line1\ninserted\nline2"));
    }

    #[test]
    fn test_insert_after_not_found() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\n").unwrap();

        let result = apply_insert_after(dir.path(), path, "nonexistent", "inserted");
        assert!(result.is_err());

        match result.unwrap_err() {
            EditError::AnchorNotFound { .. } => (),
            e => panic!("Expected AnchorNotFound, got {:?}", e),
        }
    }

    #[test]
    fn test_insert_at_line_out_of_range() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\n").unwrap();

        let result = apply_insert_at_line(dir.path(), path, 100, "inserted");
        assert!(result.is_err());

        match result.unwrap_err() {
            EditError::LineOutOfRange { .. } => (),
            e => panic!("Expected LineOutOfRange, got {:?}", e),
        }
    }
}
