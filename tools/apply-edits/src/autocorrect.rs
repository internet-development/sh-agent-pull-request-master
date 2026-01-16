// NOTE(angeldev)
// Auto-correction suggestions for failed edits.
// Attempts to automatically fix common edit failures like indentation mismatches.

use crate::error::ClosestMatch;
use crate::indent::detect_indent_style;
use crate::matcher::{normalize_indentation, find_closest_matches};

// NOTE(angeldev)
// Represents a suggested auto-correction for a failed edit.
#[derive(Debug, Clone)]
pub struct AutoCorrection {
    /// The original search string that failed
    pub original_search: String,
    /// The suggested corrected search string
    pub suggested_search: String,
    /// Confidence level (0.0 to 1.0) that this correction is correct
    pub confidence: f64,
    /// Human-readable reason for the suggestion
    pub reason: String,
    /// The type of correction applied
    pub correction_type: CorrectionType,
}

// NOTE(angeldev)
// Types of auto-corrections that can be suggested.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CorrectionType {
    /// Indentation was adjusted
    IndentationFix,
    /// Whitespace normalized
    WhitespaceFix,
    /// Trailing whitespace removed
    TrailingWhitespace,
    /// Line ending normalization (CRLF -> LF)
    LineEndingFix,
    /// Best fuzzy match found
    FuzzyMatch,
    /// Typo correction (single character difference)
    TypoFix,
}

// NOTE(angeldev)
// Suggests an auto-correction for a failed search.
// Returns None if no confident correction can be made.
pub fn suggest_correction(
    content: &str,
    search: &str,
    closest_matches: &[ClosestMatch],
    file_ext: &str,
) -> Option<AutoCorrection> {
    // Try corrections in order of preference

    // 1. Check if indentation is the only difference
    if let Some(correction) = try_indentation_correction(content, search, file_ext) {
        return Some(correction);
    }

    // 2. Check if trailing whitespace is the issue
    if let Some(correction) = try_trailing_whitespace_correction(content, search) {
        return Some(correction);
    }

    // 3. Check if line endings are the issue (CRLF vs LF)
    if let Some(correction) = try_line_ending_correction(content, search) {
        return Some(correction);
    }

    // 4. Check closest matches for high-confidence suggestions
    if let Some(correction) = try_fuzzy_match_correction(search, closest_matches) {
        return Some(correction);
    }

    // 5. Check for single-character typos
    if let Some(correction) = try_typo_correction(content, search) {
        return Some(correction);
    }

    None
}

// NOTE(angeldev)
// Tries to correct indentation differences.
fn try_indentation_correction(
    content: &str,
    search: &str,
    file_ext: &str,
) -> Option<AutoCorrection> {
    let file_style = detect_indent_style(content, file_ext);

    // Normalize both and see if they match
    let norm_content = normalize_indentation(content);
    let norm_search = normalize_indentation(search);

    if !norm_content.contains(&norm_search) {
        return None;
    }

    // Find the actual indentation in the file
    let search_lines: Vec<&str> = norm_search.lines().collect();
    if search_lines.is_empty() {
        return None;
    }

    // Find where the normalized search appears in normalized content
    let content_lines: Vec<&str> = content.lines().collect();

    for start_idx in 0..content_lines.len() {
        let end_idx = start_idx + search_lines.len();
        if end_idx > content_lines.len() {
            break;
        }

        // Check if this window matches when normalized
        let window_matches = content_lines[start_idx..end_idx]
            .iter()
            .zip(search_lines.iter())
            .all(|(content_line, search_line)| content_line.trim() == *search_line);

        if window_matches {
            // Extract the actual content with correct indentation
            let actual_content: String = content_lines[start_idx..end_idx]
                .iter()
                .map(|s| *s)
                .collect::<Vec<_>>()
                .join("\n");

            let search_first_indent = search.lines().next()
                .map(|l| l.len() - l.trim_start().len())
                .unwrap_or(0);
            let actual_first_indent = content_lines[start_idx]
                .len()
                .saturating_sub(content_lines[start_idx].trim_start().len());

            let reason = format!(
                "Search had {} leading spaces, file has {} ({:?})",
                search_first_indent,
                actual_first_indent,
                file_style
            );

            return Some(AutoCorrection {
                original_search: search.to_string(),
                suggested_search: actual_content,
                confidence: 0.95,
                reason,
                correction_type: CorrectionType::IndentationFix,
            });
        }
    }

    None
}

// NOTE(angeldev)
// Tries to correct trailing whitespace differences.
fn try_trailing_whitespace_correction(content: &str, search: &str) -> Option<AutoCorrection> {
    // Trim trailing whitespace from each line
    let trimmed_search: String = search
        .lines()
        .map(|l| l.trim_end())
        .collect::<Vec<_>>()
        .join("\n");

    if trimmed_search == search {
        return None; // No trailing whitespace to trim
    }

    if content.contains(&trimmed_search) {
        return Some(AutoCorrection {
            original_search: search.to_string(),
            suggested_search: trimmed_search,
            confidence: 0.9,
            reason: "Removed trailing whitespace from search string".to_string(),
            correction_type: CorrectionType::TrailingWhitespace,
        });
    }

    None
}

// NOTE(angeldev)
// Tries to correct line ending differences (CRLF vs LF).
fn try_line_ending_correction(content: &str, search: &str) -> Option<AutoCorrection> {
    // Check if search has CRLF but content uses LF
    if search.contains("\r\n") && !content.contains("\r\n") {
        let lf_search = search.replace("\r\n", "\n");
        if content.contains(&lf_search) {
            return Some(AutoCorrection {
                original_search: search.to_string(),
                suggested_search: lf_search,
                confidence: 0.95,
                reason: "Converted CRLF to LF line endings".to_string(),
                correction_type: CorrectionType::LineEndingFix,
            });
        }
    }

    // Check if content has CRLF but search uses LF
    if content.contains("\r\n") && !search.contains("\r\n") {
        let crlf_search = search.replace('\n', "\r\n");
        if content.contains(&crlf_search) {
            return Some(AutoCorrection {
                original_search: search.to_string(),
                suggested_search: crlf_search,
                confidence: 0.95,
                reason: "Converted LF to CRLF line endings".to_string(),
                correction_type: CorrectionType::LineEndingFix,
            });
        }
    }

    None
}

// NOTE(angeldev)
// Tries to use the best fuzzy match as a correction.
fn try_fuzzy_match_correction(
    search: &str,
    closest_matches: &[ClosestMatch],
) -> Option<AutoCorrection> {
    if closest_matches.is_empty() {
        return None;
    }

    let best = &closest_matches[0];

    // Only suggest if similarity is very high (>90%)
    if best.similarity >= 0.90 {
        return Some(AutoCorrection {
            original_search: search.to_string(),
            suggested_search: best.content.clone(),
            confidence: best.similarity,
            reason: format!(
                "Found {}% similar content at line {}",
                (best.similarity * 100.0) as u32,
                best.line
            ),
            correction_type: CorrectionType::FuzzyMatch,
        });
    }

    None
}

// NOTE(angeldev)
// Tries to correct single-character typos.
fn try_typo_correction(content: &str, search: &str) -> Option<AutoCorrection> {
    // Only try for relatively short search strings
    if search.len() > 200 || search.len() < 5 {
        return None;
    }

    // Try single character deletions
    for i in 0..search.len() {
        let mut candidate = search.to_string();
        candidate.remove(i);

        if content.contains(&candidate) {
            return Some(AutoCorrection {
                original_search: search.to_string(),
                suggested_search: candidate,
                confidence: 0.85,
                reason: format!("Removed extra character at position {}", i),
                correction_type: CorrectionType::TypoFix,
            });
        }
    }

    // Try single character insertions and substitutions is more complex
    // and might produce false positives, so we skip those

    None
}

// NOTE(angeldev)
// Applies auto-correction if confidence is above threshold.
/// Returns the corrected search string if correction was applied, None otherwise.
pub fn apply_auto_correction(
    content: &str,
    search: &str,
    file_ext: &str,
    confidence_threshold: f64,
) -> Option<(String, AutoCorrection)> {
    let closest = find_closest_matches(content, search, 0.5, 3);

    if let Some(correction) = suggest_correction(content, search, &closest, file_ext) {
        if correction.confidence >= confidence_threshold {
            return Some((correction.suggested_search.clone(), correction));
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_indentation_correction() {
        let content = "function foo() {\n    if (x) {\n        return x;\n    }\n}";
        // Search has wrong indentation (2 spaces instead of 4)
        let search = "  if (x) {\n      return x;\n  }";

        let correction = try_indentation_correction(content, search, "js");
        assert!(correction.is_some());

        let c = correction.unwrap();
        assert_eq!(c.correction_type, CorrectionType::IndentationFix);
        assert!(c.suggested_search.contains("    if (x)")); // Should have 4-space indent
    }

    #[test]
    fn test_trailing_whitespace_correction() {
        let content = "hello world\ngoodbye world";
        let search = "hello world  \ngoodbye world"; // Has trailing spaces

        let correction = try_trailing_whitespace_correction(content, search);
        assert!(correction.is_some());

        let c = correction.unwrap();
        assert_eq!(c.correction_type, CorrectionType::TrailingWhitespace);
        assert_eq!(c.suggested_search, "hello world\ngoodbye world");
    }

    #[test]
    fn test_line_ending_correction() {
        let content = "hello\nworld";
        let search = "hello\r\nworld"; // CRLF

        let correction = try_line_ending_correction(content, search);
        assert!(correction.is_some());

        let c = correction.unwrap();
        assert_eq!(c.correction_type, CorrectionType::LineEndingFix);
        assert_eq!(c.suggested_search, "hello\nworld");
    }

    #[test]
    fn test_fuzzy_match_correction() {
        let closest = vec![ClosestMatch {
            line: 5,
            similarity: 0.95,
            content: "function foo()".to_string(),
            context_before: vec![],
            context_after: vec![],
        }];

        let correction = try_fuzzy_match_correction("function fooo()", &closest);
        assert!(correction.is_some());

        let c = correction.unwrap();
        assert_eq!(c.correction_type, CorrectionType::FuzzyMatch);
    }
}
