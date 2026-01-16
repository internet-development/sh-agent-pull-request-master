// NOTE(jimmylee)
// File reading operations with line number formatting.
// Provides formatted file content for the Engineer's context.

use serde::Serialize;
use std::fs;
use std::path::Path;

// NOTE(jimmylee)
// Result of reading a single file.
#[derive(Debug, Serialize)]
pub struct FileReadResult {
    pub path: String,
    pub exists: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lines: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bytes: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub truncated: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_with_line_numbers: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

// NOTE(jimmylee)
// Result of reading multiple files.
#[derive(Debug, Serialize)]
pub struct MultiFileReadResult {
    pub files: Vec<FileReadResult>,
}

// NOTE(jimmylee)
// Reads a file and returns content with line numbers.
// Line format: "  1 | code here"
pub fn read_file_with_line_numbers(
    workdir: &Path,
    path: &str,
    max_lines: Option<usize>,
) -> FileReadResult {
    let file_path = workdir.join(path);

    if !file_path.exists() {
        return FileReadResult {
            path: path.to_string(),
            exists: false,
            lines: None,
            bytes: None,
            truncated: None,
            content: None,
            content_with_line_numbers: None,
            error: None,
        };
    }

    match fs::read_to_string(&file_path) {
        Ok(content) => {
            let total_lines = content.lines().count();
            let total_bytes = content.len();
            let max = max_lines.unwrap_or(500);
            let truncated = total_lines > max;

            // Add line numbers
            let content_with_numbers = add_line_numbers(&content, max);

            // Also provide raw content (truncated if necessary)
            let raw_content: String = content.lines().take(max).collect::<Vec<_>>().join("\n");

            FileReadResult {
                path: path.to_string(),
                exists: true,
                lines: Some(total_lines),
                bytes: Some(total_bytes),
                truncated: Some(truncated),
                content: Some(raw_content),
                content_with_line_numbers: Some(content_with_numbers),
                error: None,
            }
        }
        Err(e) => FileReadResult {
            path: path.to_string(),
            exists: true,
            lines: None,
            bytes: None,
            truncated: None,
            content: None,
            content_with_line_numbers: None,
            error: Some(e.to_string()),
        },
    }
}

// NOTE(jimmylee)
// Reads multiple files and returns results for each.
pub fn read_files_with_line_numbers(
    workdir: &Path,
    paths: &[String],
    max_lines: Option<usize>,
) -> MultiFileReadResult {
    let files = paths
        .iter()
        .map(|path| read_file_with_line_numbers(workdir, path, max_lines))
        .collect();

    MultiFileReadResult { files }
}

// NOTE(jimmylee)
// Adds line numbers to content.
// Format: "  1 | line content"
// Pads line numbers to align properly based on total line count.
fn add_line_numbers(content: &str, max_lines: usize) -> String {
    let lines: Vec<&str> = content.lines().collect();
    let total = lines.len().min(max_lines);

    // Calculate padding width based on number of digits needed
    let width = if total == 0 {
        1
    } else {
        (total as f64).log10().floor() as usize + 1
    };

    let mut result = String::new();

    for (i, line) in lines.iter().take(max_lines).enumerate() {
        let line_num = i + 1;
        result.push_str(&format!("{:>width$} | {}\n", line_num, line, width = width));
    }

    // Indicate truncation if needed
    if lines.len() > max_lines {
        result.push_str(&format!(
            "{:>width$} | ... ({} more lines)\n",
            "...",
            lines.len() - max_lines,
            width = width
        ));
    }

    // Remove trailing newline if original didn't have one
    if !content.ends_with('\n') && result.ends_with('\n') {
        result.pop();
    }

    result
}

// NOTE(jimmylee)
// Formats file read results as a human-readable string for prompts.
// Format suitable for embedding in LLM context.
pub fn format_for_prompt(results: &MultiFileReadResult) -> String {
    let mut output = String::new();

    for file in &results.files {
        if file.exists {
            let lines_info = file
                .lines
                .map(|l| format!("{} lines", l))
                .unwrap_or_default();
            let truncated_info = if file.truncated.unwrap_or(false) {
                " (truncated)"
            } else {
                ""
            };

            output.push_str(&format!(
                "### {} ({}{})\n\n",
                file.path, lines_info, truncated_info
            ));

            if let Some(ref content) = file.content_with_line_numbers {
                // Detect file extension for syntax highlighting hint
                let ext = Path::new(&file.path)
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("");

                output.push_str(&format!("```{}\n{}\n```\n\n", ext, content));
            } else if let Some(ref error) = file.error {
                output.push_str(&format!("*Error reading file: {}*\n\n", error));
            }
        } else {
            output.push_str(&format!(
                "### {}\n\n*File does not exist - will be created*\n\n",
                file.path
            ));
        }
    }

    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn test_add_line_numbers() {
        let content = "line1\nline2\nline3";
        let result = add_line_numbers(content, 100);
        assert!(result.contains("1 | line1"));
        assert!(result.contains("2 | line2"));
        assert!(result.contains("3 | line3"));
    }

    #[test]
    fn test_add_line_numbers_padding() {
        let content = (1..=12).map(|i| format!("line{}", i)).collect::<Vec<_>>().join("\n");
        let result = add_line_numbers(&content, 100);
        // Should have proper padding for double-digit lines
        assert!(result.contains(" 1 | line1"));
        assert!(result.contains("10 | line10"));
        assert!(result.contains("12 | line12"));
    }

    #[test]
    fn test_add_line_numbers_truncation() {
        let content = (1..=100).map(|i| format!("line{}", i)).collect::<Vec<_>>().join("\n");
        let result = add_line_numbers(&content, 10);
        assert!(result.contains("1 | line1"));
        assert!(result.contains("10 | line10"));
        assert!(result.contains("... (90 more lines)"));
        assert!(!result.contains("line11"));
    }

    #[test]
    fn test_read_file_with_line_numbers() {
        let dir = tempdir().unwrap();
        let path = "test.txt";
        fs::write(dir.path().join(path), "line1\nline2\nline3\n").unwrap();

        let result = read_file_with_line_numbers(dir.path(), path, Some(100));
        assert!(result.exists);
        assert_eq!(result.lines, Some(3));
        assert!(result.content_with_line_numbers.is_some());

        let content = result.content_with_line_numbers.unwrap();
        assert!(content.contains("1 | line1"));
        assert!(content.contains("3 | line3"));
    }

    #[test]
    fn test_read_file_not_exists() {
        let dir = tempdir().unwrap();
        let result = read_file_with_line_numbers(dir.path(), "nonexistent.txt", None);
        assert!(!result.exists);
        assert!(result.content.is_none());
    }

    #[test]
    fn test_format_for_prompt() {
        let results = MultiFileReadResult {
            files: vec![
                FileReadResult {
                    path: "src/main.rs".to_string(),
                    exists: true,
                    lines: Some(10),
                    bytes: Some(200),
                    truncated: Some(false),
                    content: Some("fn main() {}".to_string()),
                    content_with_line_numbers: Some("1 | fn main() {}".to_string()),
                    error: None,
                },
                FileReadResult {
                    path: "new_file.rs".to_string(),
                    exists: false,
                    lines: None,
                    bytes: None,
                    truncated: None,
                    content: None,
                    content_with_line_numbers: None,
                    error: None,
                },
            ],
        };

        let output = format_for_prompt(&results);
        assert!(output.contains("### src/main.rs (10 lines)"));
        assert!(output.contains("```rs"));
        assert!(output.contains("1 | fn main()"));
        assert!(output.contains("### new_file.rs"));
        assert!(output.contains("will be created"));
    }
}
