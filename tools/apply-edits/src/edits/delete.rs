// NOTE(jimmylee)
// Delete edit operations.
// Handles delete_file, delete_lines, and delete_match.

use crate::edits::{read_file, write_file};
use crate::error::{EditError, EditResult};
use crate::matcher::{delete_line_range, delete_matching_lines};
use std::path::Path;

// NOTE(jimmylee)
// Applies a delete_file operation.
// Deletes the specified file if it exists.
pub fn apply_delete_file(workdir: &Path, path: &str) -> EditResult<String> {
    let file_path = workdir.join(path);

    if !file_path.exists() {
        // File doesn't exist - this is a warning, not an error
        return Ok("File did not exist (already deleted)".to_string());
    }

    std::fs::remove_file(&file_path).map_err(|e| EditError::DeleteError {
        path: path.to_string(),
        reason: e.to_string(),
    })?;

    Ok("Deleted file".to_string())
}

// NOTE(jimmylee)
// Applies a delete_lines operation.
// Deletes lines from start_line to end_line (1-indexed, inclusive).
pub fn apply_delete_lines(
    workdir: &Path,
    path: &str,
    start_line: usize,
    end_line: usize,
) -> EditResult<String> {
    let content = read_file(workdir, path)?;
    let total_lines = content.lines().count();

    // Validate line numbers
    if start_line == 0 || end_line == 0 {
        return Err(EditError::InvalidEdit {
            reason: "Line numbers must be >= 1".to_string(),
        });
    }

    if start_line > end_line {
        return Err(EditError::InvalidEdit {
            reason: format!(
                "Start line ({}) must be <= end line ({})",
                start_line, end_line
            ),
        });
    }

    if end_line > total_lines {
        return Err(EditError::InvalidLineRange {
            path: path.to_string(),
            start_line,
            end_line,
            total_lines,
        });
    }

    // Delete the line range
    match delete_line_range(&content, start_line, end_line) {
        Some(new_content) => {
            write_file(workdir, path, &new_content)?;
            let deleted = end_line - start_line + 1;
            if deleted == 1 {
                Ok(format!("Deleted line {}", start_line))
            } else {
                Ok(format!("Deleted {} lines ({}-{})", deleted, start_line, end_line))
            }
        }
        None => Err(EditError::InvalidLineRange {
            path: path.to_string(),
            start_line,
            end_line,
            total_lines,
        }),
    }
}

// NOTE(jimmylee)
// Applies a delete_match operation.
// Deletes all lines containing the search string.
pub fn apply_delete_match(workdir: &Path, path: &str, search: &str) -> EditResult<String> {
    let content = read_file(workdir, path)?;

    // Validate search is not empty
    if search.is_empty() {
        return Err(EditError::InvalidEdit {
            reason: "Search string cannot be empty".to_string(),
        });
    }

    let (new_content, deleted_count) = delete_matching_lines(&content, search);

    if deleted_count == 0 {
        // No matches - this is a warning, not an error for delete_match
        return Ok("No matching lines found (nothing deleted)".to_string());
    }

    write_file(workdir, path, &new_content)?;

    if deleted_count == 1 {
        Ok("Deleted 1 matching line".to_string())
    } else {
        Ok(format!("Deleted {} matching lines", deleted_count))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_delete_file() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "content").unwrap();

        let result = apply_delete_file(dir.path(), path);
        assert!(result.is_ok());
        assert!(!dir.path().join(path).exists());
    }

    #[test]
    fn test_delete_file_not_exists() {
        let dir = tempdir().unwrap();

        let result = apply_delete_file(dir.path(), "nonexistent.txt");
        assert!(result.is_ok());
        assert!(result.unwrap().contains("already deleted"));
    }

    #[test]
    fn test_delete_lines() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\nline4\n").unwrap();

        let result = apply_delete_lines(dir.path(), path, 2, 3);
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("line1"));
        assert!(content.contains("line4"));
        assert!(!content.contains("line2"));
        assert!(!content.contains("line3"));
    }

    #[test]
    fn test_delete_lines_invalid_range() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\n").unwrap();

        let result = apply_delete_lines(dir.path(), path, 3, 5);
        assert!(result.is_err());
    }

    #[test]
    fn test_delete_match() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "keep\ndelete this\nkeep\ndelete this too\n").unwrap();

        let result = apply_delete_match(dir.path(), path, "delete");
        assert!(result.is_ok());
        assert!(result.unwrap().contains("2"));

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("keep"));
        assert!(!content.contains("delete"));
    }

    #[test]
    fn test_delete_match_no_matches() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\n").unwrap();

        let result = apply_delete_match(dir.path(), path, "nonexistent");
        assert!(result.is_ok());
        assert!(result.unwrap().contains("nothing deleted"));
    }
}
