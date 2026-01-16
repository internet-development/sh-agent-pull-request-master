// NOTE(jimmylee)
// File operations for edits.
// Handles create, append, and prepend operations.

use crate::edits::{read_file, write_file};
use crate::error::{EditError, EditResult};
use std::fs;
use std::path::Path;

// NOTE(jimmylee)
// Applies a create operation.
// Creates a new file with the given content.
// Creates parent directories if they don't exist.
pub fn apply_create(workdir: &Path, path: &str, content: &str) -> EditResult<String> {
    let file_path = workdir.join(path);

    // Create parent directories if needed
    if let Some(parent) = file_path.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent).map_err(|e| EditError::DirectoryError {
                path: parent.display().to_string(),
                reason: e.to_string(),
            })?;
        }
    }

    // Write the file
    fs::write(&file_path, content).map_err(|e| EditError::WriteError {
        path: path.to_string(),
        reason: e.to_string(),
    })?;

    let lines = content.lines().count();
    let bytes = content.len();

    Ok(format!("Created file ({} lines, {} bytes)", lines, bytes))
}

// NOTE(jimmylee)
// Applies an append operation.
// Appends content to the end of an existing file.
pub fn apply_append(workdir: &Path, path: &str, content: &str) -> EditResult<String> {
    let file_content = read_file(workdir, path)?;

    // Ensure there's a newline before appending if file doesn't end with one
    let new_content = if file_content.ends_with('\n') || file_content.is_empty() {
        format!("{}{}", file_content, content)
    } else {
        format!("{}\n{}", file_content, content)
    };

    write_file(workdir, path, &new_content)?;

    let appended_lines = content.lines().count();
    Ok(format!("Appended {} line(s)", appended_lines))
}

// NOTE(jimmylee)
// Applies a prepend operation.
// Prepends content to the beginning of an existing file.
pub fn apply_prepend(workdir: &Path, path: &str, content: &str) -> EditResult<String> {
    let file_content = read_file(workdir, path)?;

    // Ensure there's a newline after prepending
    let new_content = if content.ends_with('\n') {
        format!("{}{}", content, file_content)
    } else {
        format!("{}\n{}", content, file_content)
    };

    write_file(workdir, path, &new_content)?;

    let prepended_lines = content.lines().count();
    Ok(format!("Prepended {} line(s)", prepended_lines))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_create() {
        let dir = tempdir().unwrap();
        let path = "test.txt";

        let result = apply_create(dir.path(), path, "hello world");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "hello world");
    }

    #[test]
    fn test_create_with_dirs() {
        let dir = tempdir().unwrap();
        let path = "foo/bar/test.txt";

        let result = apply_create(dir.path(), path, "content");
        assert!(result.is_ok());
        assert!(dir.path().join(path).exists());
    }

    #[test]
    fn test_append() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\n").unwrap();

        let result = apply_append(dir.path(), path, "line2\n");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "line1\nline2\n");
    }

    #[test]
    fn test_append_no_trailing_newline() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1").unwrap();

        let result = apply_append(dir.path(), path, "line2");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "line1\nline2");
    }

    #[test]
    fn test_prepend() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line2\n").unwrap();

        let result = apply_prepend(dir.path(), path, "line1");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.starts_with("line1"));
        assert!(content.contains("line2"));
    }
}
