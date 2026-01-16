// NOTE(jimmylee)
// String matching utilities for the apply-edits tool.
// Provides literal string matching, fuzzy matching, and similarity scoring.

use crate::error::ClosestMatch;
use strsim::normalized_levenshtein;

// NOTE(jimmylee)
// Finds the first occurrence of a literal search string in content.
// Returns the byte position if found, None otherwise.
// This is intentionally NOT regex - we want exact literal matching.
pub fn find_literal(content: &str, search: &str) -> Option<usize> {
    content.find(search)
}

// NOTE(jimmylee)
// Counts occurrences of a literal search string in content.
pub fn count_occurrences(content: &str, search: &str) -> usize {
    content.matches(search).count()
}

// NOTE(jimmylee)
// Replaces the first occurrence of search with replace.
// Returns None if search string not found.
pub fn replace_first(content: &str, search: &str, replace: &str) -> Option<String> {
    content.find(search).map(|pos| {
        let mut result = String::with_capacity(content.len() - search.len() + replace.len());
        result.push_str(&content[..pos]);
        result.push_str(replace);
        result.push_str(&content[pos + search.len()..]);
        result
    })
}

// NOTE(jimmylee)
// Replaces all occurrences of search with replace.
// This is a literal string replacement, not regex.
pub fn replace_all(content: &str, search: &str, replace: &str) -> String {
    content.replace(search, replace)
}

// NOTE(jimmylee)
// Finds the line number (1-indexed) containing the given anchor string.
// Returns the first matching line number if found.
pub fn find_line_with_anchor(content: &str, anchor: &str) -> Option<usize> {
    for (i, line) in content.lines().enumerate() {
        if line.contains(anchor) {
            return Some(i + 1); // 1-indexed
        }
    }
    None
}

// NOTE(jimmylee)
// Normalizes whitespace in a string for fuzzy comparison.
// - Trims trailing whitespace from each line
// - Removes carriage returns
// - Preserves leading whitespace (indentation matters in code)
pub fn normalize_whitespace(s: &str) -> String {
    s.lines()
        .map(|line| line.trim_end())
        .collect::<Vec<_>>()
        .join("\n")
}

// NOTE(angeldev)
// Normalizes indentation by trimming all leading/trailing whitespace from each line.
// Used for fuzzy matching when indentation differs between search and content.
pub fn normalize_indentation(s: &str) -> String {
    s.lines()
        .map(|line| line.trim())
        .collect::<Vec<_>>()
        .join("\n")
}

// NOTE(jimmylee)
// Result of attempting to find a string with optional normalization.
#[derive(Debug)]
pub enum FindResult {
    // Exact match found at byte position
    Exact(usize),
    // Match found only after whitespace normalization
    NormalizedMatch { warning: String, line_number: usize },
    // No match found
    NotFound,
}

// NOTE(angeldev)
// Attempts to find a search string, falling back to indentation-normalized matching.
// When indentation differs, returns the line number where the match was found so
// the caller can extract the actual content with correct indentation.
pub fn find_with_normalization(content: &str, search: &str) -> FindResult {
    // Try exact match first
    if let Some(pos) = content.find(search) {
        return FindResult::Exact(pos);
    }

    // Try indentation-normalized match (handles cases where LLM used wrong indentation)
    let norm_search = normalize_indentation(search);
    let search_lines: Vec<&str> = norm_search.lines().collect();
    
    if search_lines.is_empty() {
        return FindResult::NotFound;
    }
    
    let content_lines: Vec<&str> = content.lines().collect();
    
    // Sliding window search with normalized comparison
    for start_idx in 0..content_lines.len() {
        let end_idx = start_idx + search_lines.len();
        if end_idx > content_lines.len() {
            break;
        }
        
        // Check if this window matches when both are normalized
        let window_matches = content_lines[start_idx..end_idx]
            .iter()
            .zip(search_lines.iter())
            .all(|(content_line, search_line)| {
                content_line.trim() == *search_line
            });
        
        if window_matches {
            return FindResult::NormalizedMatch {
                warning: format!(
                    "Exact match failed due to indentation differences. Found matching content at line {} with different whitespace.",
                    start_idx + 1
                ),
                line_number: start_idx + 1,
            };
        }
    }

    FindResult::NotFound
}

// NOTE(angeldev)
// Extracts the actual content from a file at the given line range, preserving original indentation.
// Used after find_with_normalization finds a match with different indentation.
pub fn extract_lines(content: &str, start_line: usize, line_count: usize) -> String {
    content
        .lines()
        .skip(start_line.saturating_sub(1))
        .take(line_count)
        .collect::<Vec<_>>()
        .join("\n")
}

// NOTE(angeldev)
// Performs a replacement using indentation-normalized matching.
// When the search string has different indentation than the file, this function:
// 1. Finds the matching content using normalized comparison
// 2. Extracts the actual content with correct indentation
// 3. Replaces that actual content with the replacement (adjusted for correct indentation)
pub fn replace_with_normalization(content: &str, search: &str, replace: &str) -> Option<(String, String)> {
    match find_with_normalization(content, search) {
        FindResult::Exact(pos) => {
            // Exact match - use simple replacement
            let mut result = String::with_capacity(content.len() - search.len() + replace.len());
            result.push_str(&content[..pos]);
            result.push_str(replace);
            result.push_str(&content[pos + search.len()..]);
            Some((result, "Exact match".to_string()))
        }
        FindResult::NormalizedMatch { warning, line_number } => {
            // Indentation mismatch - need to extract actual content and adjust replacement
            let search_line_count = search.lines().count();
            let actual_search = extract_lines(content, line_number, search_line_count);
            
            // Detect the indentation difference
            let search_first_line = search.lines().next().unwrap_or("");
            let actual_first_line = actual_search.lines().next().unwrap_or("");
            
            let search_indent = search_first_line.len() - search_first_line.trim_start().len();
            let actual_indent = actual_first_line.len() - actual_first_line.trim_start().len();
            
            // Adjust the replacement to use the file's actual indentation
            let adjusted_replace = if actual_indent != search_indent {
                adjust_indentation(replace, search_indent, actual_indent)
            } else {
                replace.to_string()
            };
            
            // Now perform the replacement with the actual content
            if let Some(pos) = content.find(&actual_search) {
                let mut result = String::with_capacity(content.len() - actual_search.len() + adjusted_replace.len());
                result.push_str(&content[..pos]);
                result.push_str(&adjusted_replace);
                result.push_str(&content[pos + actual_search.len()..]);
                Some((result, warning))
            } else {
                None
            }
        }
        FindResult::NotFound => None,
    }
}

// NOTE(angeldev)
// Adjusts the indentation of a multi-line string from one level to another.
// If the original has 14-space indent but file uses 16-space, this adjusts all lines.
fn adjust_indentation(text: &str, from_indent: usize, to_indent: usize) -> String {
    text.lines()
        .map(|line| {
            let line_indent = line.len() - line.trim_start().len();
            if line_indent >= from_indent {
                // Calculate relative indentation and apply to new base
                let relative_indent = line_indent - from_indent;
                let new_indent = to_indent + relative_indent;
                format!("{}{}", " ".repeat(new_indent), line.trim_start())
            } else {
                // Line has less indentation than expected, keep as-is
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

// NOTE(jimmylee)
// Finds the closest matching content in a file when exact match fails.
// Uses sliding window over lines and Levenshtein distance for similarity.
// Returns matches above the threshold, sorted by similarity descending.
pub fn find_closest_matches(
    content: &str,
    search: &str,
    threshold: f64,
    max_results: usize,
) -> Vec<ClosestMatch> {
    let search_lines: Vec<&str> = search.lines().collect();
    let content_lines: Vec<&str> = content.lines().collect();

    if search_lines.is_empty() || content_lines.is_empty() {
        return Vec::new();
    }

    let mut matches = Vec::new();
    let window_size = search_lines.len();

    // Sliding window over content lines
    for start in 0..content_lines.len() {
        let end = (start + window_size).min(content_lines.len());
        let window: String = content_lines[start..end].join("\n");

        let similarity = normalized_levenshtein(search, &window);

        if similarity >= threshold {
            // Get context (2 lines before and after)
            let context_before: Vec<String> = content_lines
                [start.saturating_sub(2)..start]
                .iter()
                .map(|s| s.to_string())
                .collect();

            let context_after: Vec<String> = content_lines
                [end..(end + 2).min(content_lines.len())]
                .iter()
                .map(|s| s.to_string())
                .collect();

            matches.push(ClosestMatch {
                line: start + 1, // 1-indexed
                similarity,
                content: window,
                context_before,
                context_after,
            });
        }
    }

    // Sort by similarity descending
    matches.sort_by(|a, b| {
        b.similarity
            .partial_cmp(&a.similarity)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Take top results
    matches.truncate(max_results);
    matches
}

// NOTE(jimmylee)
// Truncates a string to max_len characters, adding "..." if truncated.
pub fn truncate_preview(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len.saturating_sub(3)])
    }
}

// NOTE(jimmylee)
// Gets the line number (1-indexed) for a byte position in content.
pub fn byte_pos_to_line(content: &str, pos: usize) -> usize {
    content[..pos].lines().count().max(1)
}

// NOTE(jimmylee)
// Gets a range of lines affected by a replacement.
// Returns (start_line, end_line) as 1-indexed values.
pub fn get_affected_lines(content: &str, pos: usize, old_len: usize) -> (usize, usize) {
    let start_line = byte_pos_to_line(content, pos);
    let end_pos = pos + old_len;
    let end_line = byte_pos_to_line(content, end_pos.min(content.len()));
    (start_line, end_line)
}

// NOTE(jimmylee)
// Inserts content after the line containing the anchor.
// Returns the new content and the line number where insertion occurred.
pub fn insert_after_line(content: &str, anchor: &str, new_content: &str) -> Option<(String, usize)> {
    let lines: Vec<&str> = content.lines().collect();

    for (i, line) in lines.iter().enumerate() {
        if line.contains(anchor) {
            let mut result = String::new();

            // Lines before and including the anchor line
            for (j, l) in lines.iter().enumerate() {
                result.push_str(l);
                if j <= i {
                    result.push('\n');
                } else if j < lines.len() - 1 {
                    result.push('\n');
                }

                // Insert after anchor line
                if j == i {
                    result.push_str(new_content);
                    result.push('\n');
                }
            }

            // Handle trailing newline
            if content.ends_with('\n') && !result.ends_with('\n') {
                result.push('\n');
            }

            return Some((result, i + 2)); // Line after anchor (1-indexed)
        }
    }

    None
}

// NOTE(jimmylee)
// Inserts content before the line containing the anchor.
// Returns the new content and the line number where insertion occurred.
pub fn insert_before_line(
    content: &str,
    anchor: &str,
    new_content: &str,
) -> Option<(String, usize)> {
    let lines: Vec<&str> = content.lines().collect();

    for (i, line) in lines.iter().enumerate() {
        if line.contains(anchor) {
            let mut result = String::new();

            for (j, l) in lines.iter().enumerate() {
                // Insert before anchor line
                if j == i {
                    result.push_str(new_content);
                    result.push('\n');
                }

                result.push_str(l);
                if j < lines.len() - 1 {
                    result.push('\n');
                }
            }

            // Handle trailing newline
            if content.ends_with('\n') && !result.ends_with('\n') {
                result.push('\n');
            }

            return Some((result, i + 1)); // Same line as anchor (1-indexed)
        }
    }

    None
}

// NOTE(jimmylee)
// Inserts content at a specific line number (1-indexed).
// Returns the new content.
pub fn insert_at_line(content: &str, line_num: usize, new_content: &str) -> Option<String> {
    let lines: Vec<&str> = content.lines().collect();

    if line_num == 0 || line_num > lines.len() + 1 {
        return None;
    }

    let mut result = String::new();
    let insert_index = line_num - 1; // Convert to 0-indexed

    for (i, line) in lines.iter().enumerate() {
        if i == insert_index {
            result.push_str(new_content);
            result.push('\n');
        }
        result.push_str(line);
        if i < lines.len() - 1 {
            result.push('\n');
        }
    }

    // If inserting at the end
    if insert_index >= lines.len() {
        if !result.is_empty() && !result.ends_with('\n') {
            result.push('\n');
        }
        result.push_str(new_content);
    }

    // Handle trailing newline
    if content.ends_with('\n') && !result.ends_with('\n') {
        result.push('\n');
    }

    Some(result)
}

// NOTE(jimmylee)
// Deletes lines in the given range (1-indexed, inclusive).
// Returns the new content.
pub fn delete_line_range(content: &str, start: usize, end: usize) -> Option<String> {
    let lines: Vec<&str> = content.lines().collect();

    if start == 0 || end == 0 || start > end || end > lines.len() {
        return None;
    }

    let mut result = String::new();
    let start_idx = start - 1; // Convert to 0-indexed
    let end_idx = end - 1;

    for (i, line) in lines.iter().enumerate() {
        if i < start_idx || i > end_idx {
            result.push_str(line);
            if i < lines.len() - 1 && !(i >= start_idx && i < end_idx) {
                result.push('\n');
            }
        }
    }

    // Clean up double newlines that might result from deletion
    while result.contains("\n\n\n") {
        result = result.replace("\n\n\n", "\n\n");
    }

    // Handle trailing newline
    if content.ends_with('\n') && !result.is_empty() && !result.ends_with('\n') {
        result.push('\n');
    }

    Some(result)
}

// NOTE(jimmylee)
// Deletes all lines containing the given search string.
// Returns the new content and count of lines deleted.
pub fn delete_matching_lines(content: &str, search: &str) -> (String, usize) {
    let lines: Vec<&str> = content.lines().collect();
    let mut result = Vec::new();
    let mut deleted = 0;

    for line in lines.iter() {
        if line.contains(search) {
            deleted += 1;
        } else {
            result.push(*line);
        }
    }

    let mut output = result.join("\n");

    // Handle trailing newline
    if content.ends_with('\n') && !output.is_empty() {
        output.push('\n');
    }

    (output, deleted)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_replace_first() {
        let content = "foo bar foo";
        let result = replace_first(content, "foo", "baz");
        assert_eq!(result, Some("baz bar foo".to_string()));
    }

    #[test]
    fn test_replace_all() {
        let content = "foo bar foo";
        let result = replace_all(content, "foo", "baz");
        assert_eq!(result, "baz bar baz");
    }

    #[test]
    fn test_multiline_replace() {
        let content = "line1\nfunction foo() {\n  return 1;\n}\nline5";
        let search = "function foo() {\n  return 1;\n}";
        let replace = "function bar() {\n  return 2;\n}";
        let result = replace_first(content, search, replace);
        assert_eq!(
            result,
            Some("line1\nfunction bar() {\n  return 2;\n}\nline5".to_string())
        );
    }

    #[test]
    fn test_insert_after_line() {
        let content = "line1\nline2\nline3";
        let result = insert_after_line(content, "line2", "inserted");
        assert!(result.is_some());
        let (new_content, line) = result.unwrap();
        assert!(new_content.contains("line2\ninserted\nline3"));
        assert_eq!(line, 3);
    }

    #[test]
    fn test_insert_before_line() {
        let content = "line1\nline2\nline3";
        let result = insert_before_line(content, "line2", "inserted");
        assert!(result.is_some());
        let (new_content, line) = result.unwrap();
        assert!(new_content.contains("line1\ninserted\nline2"));
        assert_eq!(line, 2);
    }

    #[test]
    fn test_delete_line_range() {
        let content = "line1\nline2\nline3\nline4";
        let result = delete_line_range(content, 2, 3);
        assert!(result.is_some());
        let new_content = result.unwrap();
        assert!(new_content.contains("line1"));
        assert!(new_content.contains("line4"));
        assert!(!new_content.contains("line2"));
        assert!(!new_content.contains("line3"));
    }

    #[test]
    fn test_normalize_whitespace() {
        let content = "line1  \nline2\t\nline3";
        let result = normalize_whitespace(content);
        assert_eq!(result, "line1\nline2\nline3");
    }
}
