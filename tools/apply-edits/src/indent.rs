// NOTE(angeldev)
// Language-aware indentation detection and normalization.
// Handles different indentation styles (spaces vs tabs) across languages.

use std::collections::HashMap;

// NOTE(angeldev)
// Represents the indentation style detected in a file.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum IndentStyle {
    // Spaces with the detected width (e.g., 2, 4, 8)
    Spaces(usize),
    // Tab-based indentation
    Tabs,
    // Mixed tabs and spaces (common in older codebases)
    Mixed,
    // Could not detect (empty or inconsistent)
    Unknown,
}

impl Default for IndentStyle {
    fn default() -> Self {
        IndentStyle::Spaces(4)
    }
}

// NOTE(angeldev)
// Language-specific indentation defaults and preferences.
pub fn language_default_indent(extension: &str) -> IndentStyle {
    match extension.to_lowercase().as_str() {
        // Go strongly prefers tabs
        "go" => IndentStyle::Tabs,

        // Python PEP 8 recommends 4 spaces
        "py" | "pyw" => IndentStyle::Spaces(4),

        // JavaScript/TypeScript ecosystem typically uses 2 spaces
        "js" | "jsx" | "ts" | "tsx" | "mjs" | "cjs" => IndentStyle::Spaces(2),

        // HTML/CSS/SCSS typically 2 spaces
        "html" | "htm" | "css" | "scss" | "sass" | "less" => IndentStyle::Spaces(2),

        // JSON/YAML typically 2 spaces
        "json" | "yaml" | "yml" => IndentStyle::Spaces(2),

        // Rust uses 4 spaces per rustfmt default
        "rs" => IndentStyle::Spaces(4),

        // Ruby typically uses 2 spaces
        "rb" => IndentStyle::Spaces(2),

        // Java/Kotlin typically 4 spaces
        "java" | "kt" | "kts" => IndentStyle::Spaces(4),

        // C/C++ varies but 4 is common
        "c" | "cpp" | "cc" | "h" | "hpp" => IndentStyle::Spaces(4),

        // C# typically 4 spaces
        "cs" => IndentStyle::Spaces(4),

        // PHP varies, 4 is PSR standard
        "php" => IndentStyle::Spaces(4),

        // Shell scripts typically 2-4, we default to 4
        "sh" | "bash" | "zsh" => IndentStyle::Spaces(4),

        // Makefile requires tabs
        "makefile" | "mk" => IndentStyle::Tabs,

        // Vue/Svelte typically 2 spaces
        "vue" | "svelte" => IndentStyle::Spaces(2),

        // Default to 4 spaces
        _ => IndentStyle::Spaces(4),
    }
}

// NOTE(angeldev)
// Detects the indentation style used in file content.
// Analyzes the first 100 lines (or all lines if fewer) to determine the dominant style.
pub fn detect_indent_style(content: &str, file_ext: &str) -> IndentStyle {
    let lines: Vec<&str> = content.lines().take(100).collect();

    if lines.is_empty() {
        return language_default_indent(file_ext);
    }

    let mut space_counts: HashMap<usize, usize> = HashMap::new();
    let mut tab_lines = 0;
    let mut space_lines = 0;
    let mut indented_lines = 0;

    for line in &lines {
        if line.is_empty() || line.trim().is_empty() {
            continue;
        }

        let leading = line.len() - line.trim_start().len();
        if leading == 0 {
            continue;
        }

        indented_lines += 1;
        let first_char = line.chars().next().unwrap();

        if first_char == '\t' {
            tab_lines += 1;
        } else if first_char == ' ' {
            space_lines += 1;
            // Track the indentation width
            *space_counts.entry(leading).or_insert(0) += 1;
        }
    }

    if indented_lines == 0 {
        return language_default_indent(file_ext);
    }

    // Determine if tabs or spaces dominate
    if tab_lines > space_lines {
        if space_lines > 0 && space_lines as f64 / indented_lines as f64 > 0.2 {
            return IndentStyle::Mixed;
        }
        return IndentStyle::Tabs;
    }

    if space_lines == 0 {
        return language_default_indent(file_ext);
    }

    // Find the most common indentation width
    // Look for the GCD of common indentation levels
    let mut widths: Vec<(usize, usize)> = space_counts.into_iter().collect();
    widths.sort_by(|a, b| b.1.cmp(&a.1));

    if let Some((most_common_width, _)) = widths.first() {
        // Find the GCD of the most common widths to detect the base indent
        let base_indent = find_indent_base(&widths);
        if base_indent > 0 && base_indent <= 8 {
            return IndentStyle::Spaces(base_indent);
        }
        if *most_common_width > 0 && *most_common_width <= 8 {
            return IndentStyle::Spaces(*most_common_width);
        }
    }

    language_default_indent(file_ext)
}

// NOTE(angeldev)
// Finds the base indentation unit from observed indentation widths.
// Uses GCD-like analysis to find the smallest common divisor.
fn find_indent_base(widths: &[(usize, usize)]) -> usize {
    // Get the top 5 most common widths
    let top_widths: Vec<usize> = widths
        .iter()
        .take(5)
        .map(|(w, _)| *w)
        .filter(|w| *w > 0)
        .collect();

    if top_widths.is_empty() {
        return 4;
    }

    // Find GCD of all observed widths
    let mut result = top_widths[0];
    for &width in &top_widths[1..] {
        result = gcd(result, width);
    }

    // Sanity check: result should be 1, 2, 4, or 8
    if result == 1 || result == 3 || result > 8 {
        // Likely not a standard indent, fall back to most common
        return *top_widths.first().unwrap_or(&4);
    }

    result
}

// NOTE(angeldev)
// Greatest common divisor (Euclidean algorithm).
fn gcd(mut a: usize, mut b: usize) -> usize {
    while b != 0 {
        let temp = b;
        b = a % b;
        a = temp;
    }
    a
}

// NOTE(angeldev)
// Normalizes indentation for comparison purposes.
// Converts both tabs and spaces to a canonical form.
pub fn normalize_for_comparison(content: &str, style: IndentStyle) -> String {
    match style {
        IndentStyle::Tabs => {
            // Convert each tab to a single marker, collapse runs of spaces
            content
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    let indent_len = line.len() - trimmed.len();
                    let indent = &line[..indent_len];

                    // Count tabs, treat runs of spaces as partial tabs
                    let tabs = indent.matches('\t').count();
                    let spaces = indent.chars().filter(|c| *c == ' ').count();
                    let effective_tabs = tabs + (spaces / 4); // Assume 4 spaces = 1 tab for comparison

                    format!("{}{}", "\t".repeat(effective_tabs), trimmed)
                })
                .collect::<Vec<_>>()
                .join("\n")
        }
        IndentStyle::Spaces(width) => {
            // Convert tabs to spaces
            content
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    let indent_len = line.len() - trimmed.len();
                    let indent = &line[..indent_len];

                    let tabs = indent.matches('\t').count();
                    let spaces = indent.chars().filter(|c| *c == ' ').count();
                    let total_spaces = (tabs * width) + spaces;

                    format!("{}{}", " ".repeat(total_spaces), trimmed)
                })
                .collect::<Vec<_>>()
                .join("\n")
        }
        IndentStyle::Mixed | IndentStyle::Unknown => {
            // Just normalize whitespace
            content
                .lines()
                .map(|line| line.trim_end().to_string())
                .collect::<Vec<_>>()
                .join("\n")
        }
    }
}

// NOTE(angeldev)
// Converts replacement text to match the target file's indentation style.
pub fn convert_to_target_style(replacement: &str, source_style: IndentStyle, target_style: IndentStyle) -> String {
    if source_style == target_style {
        return replacement.to_string();
    }

    match (source_style, target_style) {
        (IndentStyle::Spaces(src_width), IndentStyle::Spaces(tgt_width)) => {
            // Convert between different space widths
            replacement
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    let leading_spaces = line.len() - trimmed.len();

                    if leading_spaces == 0 {
                        return line.to_string();
                    }

                    // Calculate indent level in source, apply to target
                    let indent_level = leading_spaces / src_width;
                    let remainder = leading_spaces % src_width;
                    let new_spaces = (indent_level * tgt_width) + remainder;

                    format!("{}{}", " ".repeat(new_spaces), trimmed)
                })
                .collect::<Vec<_>>()
                .join("\n")
        }
        (IndentStyle::Spaces(src_width), IndentStyle::Tabs) => {
            // Convert spaces to tabs
            replacement
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    let leading_spaces = line.len() - trimmed.len();

                    if leading_spaces == 0 {
                        return line.to_string();
                    }

                    let tabs = leading_spaces / src_width;
                    let remainder = leading_spaces % src_width;

                    format!("{}{}{}", "\t".repeat(tabs), " ".repeat(remainder), trimmed)
                })
                .collect::<Vec<_>>()
                .join("\n")
        }
        (IndentStyle::Tabs, IndentStyle::Spaces(tgt_width)) => {
            // Convert tabs to spaces
            replacement
                .lines()
                .map(|line| {
                    let trimmed = line.trim_start();
                    let indent = &line[..line.len() - trimmed.len()];

                    let tabs = indent.matches('\t').count();
                    let spaces = indent.chars().filter(|c| *c == ' ').count();
                    let total_spaces = (tabs * tgt_width) + spaces;

                    format!("{}{}", " ".repeat(total_spaces), trimmed)
                })
                .collect::<Vec<_>>()
                .join("\n")
        }
        _ => replacement.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_spaces_4() {
        let content = "function foo() {\n    let x = 1;\n    if (x) {\n        return x;\n    }\n}";
        let style = detect_indent_style(content, "js");
        assert_eq!(style, IndentStyle::Spaces(4));
    }

    #[test]
    fn test_detect_spaces_2() {
        let content = "function foo() {\n  let x = 1;\n  if (x) {\n    return x;\n  }\n}";
        let style = detect_indent_style(content, "js");
        assert_eq!(style, IndentStyle::Spaces(2));
    }

    #[test]
    fn test_detect_tabs() {
        let content = "func foo() {\n\tlet x = 1\n\tif x {\n\t\treturn x\n\t}\n}";
        let style = detect_indent_style(content, "go");
        assert_eq!(style, IndentStyle::Tabs);
    }

    #[test]
    fn test_language_default() {
        assert_eq!(language_default_indent("go"), IndentStyle::Tabs);
        assert_eq!(language_default_indent("py"), IndentStyle::Spaces(4));
        assert_eq!(language_default_indent("ts"), IndentStyle::Spaces(2));
        assert_eq!(language_default_indent("rs"), IndentStyle::Spaces(4));
    }

    #[test]
    fn test_convert_spaces_to_tabs() {
        let content = "function foo() {\n    let x = 1;\n}";
        let converted = convert_to_target_style(content, IndentStyle::Spaces(4), IndentStyle::Tabs);
        assert!(converted.contains("\tlet x = 1;"));
    }

    #[test]
    fn test_convert_tabs_to_spaces() {
        let content = "function foo() {\n\tlet x = 1;\n}";
        let converted = convert_to_target_style(content, IndentStyle::Tabs, IndentStyle::Spaces(4));
        assert!(converted.contains("    let x = 1;"));
    }
}
