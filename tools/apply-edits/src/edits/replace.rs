// NOTE(jimmylee)
// Replace edit operations.
// Handles replace (first occurrence) and replace_all (all occurrences).

use crate::edits::{read_file, write_file};
use crate::error::{EditError, EditResult};
use crate::matcher::{
    count_occurrences, find_closest_matches, find_literal, get_affected_lines, replace_all,
    replace_first, replace_with_normalization, truncate_preview,
};
use std::path::Path;

// NOTE(jimmylee)
// Similarity threshold for finding closest matches when search fails.
// 0.5 = 50% similar - catches partial matches and renamed items.
const SIMILARITY_THRESHOLD: f64 = 0.5;

// NOTE(jimmylee)
// Maximum number of closest matches to return in error messages.
const MAX_CLOSEST_MATCHES: usize = 3;

// NOTE(angeldev)
// Applies a replace operation (first occurrence only).
// First tries exact match, then falls back to indentation-normalized matching.
// This handles cases where the LLM uses wrong indentation but correct content.
pub fn apply_replace(
    workdir: &Path,
    path: &str,
    search: &str,
    replace: &str,
) -> EditResult<String> {
    let content = read_file(workdir, path)?;

    // Validate search string is not empty
    if search.is_empty() {
        return Err(EditError::InvalidEdit {
            reason: "Search string cannot be empty".to_string(),
        });
    }

    // Try exact match first
    let occurrences = count_occurrences(&content, search);

    if occurrences > 0 {
        // Exact match found - perform simple replacement
        let new_content = replace_first(&content, search, replace).ok_or_else(|| {
            EditError::InvalidEdit {
                reason: "Replacement failed unexpectedly".to_string(),
            }
        })?;

        write_file(workdir, path, &new_content)?;

        if let Some(pos) = find_literal(&content, search) {
            let (start_line, end_line) = get_affected_lines(&content, pos, search.len());
            if start_line == end_line {
                return Ok(format!("Replaced 1 occurrence (line {})", start_line));
            } else {
                return Ok(format!(
                    "Replaced 1 occurrence (lines {}-{})",
                    start_line, end_line
                ));
            }
        }
        return Ok("Replaced 1 occurrence".to_string());
    }

    // Exact match failed - try indentation-normalized matching
    // This catches cases where LLM used wrong indentation but correct content
    if let Some((new_content, warning)) = replace_with_normalization(&content, search, replace) {
        write_file(workdir, path, &new_content)?;
        
        // Log that we used normalization (helpful for debugging)
        return Ok(format!(
            "Replaced with indentation adjustment ({})",
            warning
        ));
    }

    // No match even with normalization - return helpful error with closest matches
    let closest = find_closest_matches(&content, search, SIMILARITY_THRESHOLD, MAX_CLOSEST_MATCHES);

    Err(EditError::SearchNotFound {
        path: path.to_string(),
        search_preview: truncate_preview(search, 200),
        closest_matches: closest,
    })
}

// NOTE(jimmylee)
// Applies a replace_all operation (all occurrences).
// Returns a warning if no occurrences are found (not an error).
pub fn apply_replace_all(
    workdir: &Path,
    path: &str,
    search: &str,
    replace_with: &str,
) -> EditResult<String> {
    let content = read_file(workdir, path)?;

    // Validate search string is not empty
    if search.is_empty() {
        return Err(EditError::InvalidEdit {
            reason: "Search string cannot be empty".to_string(),
        });
    }

    // Count occurrences
    let occurrences = count_occurrences(&content, search);

    if occurrences == 0 {
        // For replace_all, we warn but don't fail if nothing found
        // This is different from replace which requires at least one match
        let closest = find_closest_matches(&content, search, SIMILARITY_THRESHOLD, MAX_CLOSEST_MATCHES);

        return Err(EditError::SearchNotFound {
            path: path.to_string(),
            search_preview: truncate_preview(search, 200),
            closest_matches: closest,
        });
    }

    // Perform the replacement
    let new_content = replace_all(&content, search, replace_with);

    // Write the result
    write_file(workdir, path, &new_content)?;

    Ok(format!("Replaced {} occurrence(s)", occurrences))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_apply_replace_single_line() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "hello world").unwrap();

        let result = apply_replace(dir.path(), path, "world", "rust");
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "hello rust");
    }

    #[test]
    fn test_apply_replace_multiline() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(
            dir.path().join(path),
            "function foo() {\n  return 1;\n}\n",
        )
        .unwrap();

        let result = apply_replace(
            dir.path(),
            path,
            "function foo() {\n  return 1;\n}",
            "function bar() {\n  return 2;\n}",
        );
        assert!(result.is_ok());

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("function bar()"));
        assert!(content.contains("return 2"));
    }

    #[test]
    fn test_apply_replace_not_found() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "hello world").unwrap();

        let result = apply_replace(dir.path(), path, "foo", "bar");
        assert!(result.is_err());

        match result.unwrap_err() {
            EditError::SearchNotFound { .. } => (),
            e => panic!("Expected SearchNotFound, got {:?}", e),
        }
    }

    #[test]
    fn test_apply_replace_all() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "foo bar foo baz foo").unwrap();

        let result = apply_replace_all(dir.path(), path, "foo", "qux");
        assert!(result.is_ok());
        assert!(result.unwrap().contains("3 occurrence"));

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "qux bar qux baz qux");
    }

    // NOTE(angeldev)
    // Test that indentation-normalized matching works when LLM uses wrong indentation
    #[test]
    fn test_apply_replace_with_indentation_normalization() {
        let dir = tempdir().unwrap();
        let path = "test.tsx";
        
        // File content has 16-space indentation
        let file_content = r#"const items = [
                {
                    icon: '⊹',
                    children: 'Pink',
                    onClick: () => handleClick('pink'),
                },
            ];"#;
        
        fs::write(dir.path().join(path), file_content).unwrap();

        // Search string has 14-space indentation (LLM got it wrong)
        let search = r#"              {
                  icon: '⊹',
                  children: 'Pink',
                  onClick: () => handleClick('pink'),
              },"#;
        
        // Replacement with same wrong indentation
        let replace = r#"              {
                  icon: '⊹',
                  children: 'Cherry',
                  onClick: () => handleClick('cherry'),
              },"#;

        let result = apply_replace(dir.path(), path, search, replace);
        
        // Should succeed with indentation adjustment
        assert!(result.is_ok(), "Replace should succeed with indentation normalization: {:?}", result);
        
        let msg = result.unwrap();
        assert!(msg.contains("indentation"), "Message should mention indentation adjustment: {}", msg);

        // Verify the content was replaced correctly
        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert!(content.contains("Cherry"), "Content should have 'Cherry': {}", content);
        assert!(content.contains("cherry"), "Content should have 'cherry': {}", content);
        assert!(!content.contains("Pink"), "Content should not have 'Pink': {}", content);
        
        // Verify indentation was preserved from the original file (16 spaces)
        assert!(content.contains("                {"), "Should preserve 16-space indentation");
    }

    // NOTE(angeldev)
    // Test that exact match still works and takes precedence
    #[test]
    fn test_apply_replace_exact_match_takes_precedence() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        
        let file_content = "    hello world\n    goodbye world";
        fs::write(dir.path().join(path), file_content).unwrap();

        // Exact match with correct indentation
        let result = apply_replace(dir.path(), path, "    hello world", "    hello rust");
        assert!(result.is_ok());
        
        let msg = result.unwrap();
        // Should NOT mention indentation since it was an exact match
        assert!(!msg.contains("indentation"), "Exact match should not mention indentation: {}", msg);

        let content = fs::read_to_string(dir.path().join(path)).unwrap();
        assert_eq!(content, "    hello rust\n    goodbye world");
    }
}
