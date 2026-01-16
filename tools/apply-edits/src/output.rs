// NOTE(jimmylee)
// Output formatting for the apply-edits tool.
// Provides both human-readable (colored, to stderr) and JSON (to stdout) output.

use crate::error::{ApplyResult, ClosestMatch, EditOutcome};
use colored::Colorize;
use std::io::{self, Write};

// NOTE(jimmylee)
// Prints a header line to stderr with the tool name and version.
pub fn print_header() {
    eprintln!(
        "{} {}",
        "apply-edits".bold().cyan(),
        format!("v{}", env!("CARGO_PKG_VERSION")).dimmed()
    );
}

// NOTE(jimmylee)
// Prints the working directory info to stderr.
pub fn print_workdir(workdir: &str) {
    eprintln!("{} {}", "Working directory:".dimmed(), workdir);
    eprintln!();
}

// NOTE(jimmylee)
// Prints progress for starting to process edits.
pub fn print_processing_start(count: usize) {
    eprintln!("Processing {} edit(s)...", count.to_string().bold());
    eprintln!();
}

// NOTE(jimmylee)
// Prints a successful edit result to stderr.
pub fn print_edit_success(index: usize, total: usize, edit_type: &str, path: &str, message: &str) {
    eprintln!(
        "{} {} {}",
        format!("[{}/{}]", index + 1, total).dimmed(),
        edit_type.cyan(),
        path.white()
    );
    eprintln!("      {} {}", "✓".green().bold(), message.green());
}

// NOTE(jimmylee)
// Prints a warning edit result to stderr.
pub fn print_edit_warning(
    index: usize,
    total: usize,
    edit_type: &str,
    path: &str,
    warning: &str,
    message: &str,
) {
    eprintln!(
        "{} {} {}",
        format!("[{}/{}]", index + 1, total).dimmed(),
        edit_type.cyan(),
        path.white()
    );
    eprintln!("      {} {}", "⚠".yellow().bold(), message.yellow());
    eprintln!("      {}", warning.dimmed());
}

// NOTE(jimmylee)
// Prints a failed edit result to stderr with detailed error info.
pub fn print_edit_error(
    index: usize,
    total: usize,
    edit_type: &str,
    path: &str,
    error_msg: &str,
    search_preview: Option<&str>,
    closest_matches: Option<&Vec<ClosestMatch>>,
    hint: Option<&str>,
) {
    eprintln!(
        "{} {} {}",
        format!("[{}/{}]", index + 1, total).dimmed(),
        edit_type.cyan(),
        path.white()
    );
    eprintln!("      {} {}", "✗".red().bold(), "ERROR".red().bold());
    eprintln!("      {}", error_msg.red());

    // Show search string preview
    if let Some(preview) = search_preview {
        eprintln!();
        eprintln!("      {}:", "Search string (preview)".dimmed());
        for line in preview.lines().take(5) {
            eprintln!("      {} {}", "│".dimmed(), line);
        }
        if preview.lines().count() > 5 {
            eprintln!("      {} {}", "│".dimmed(), "...".dimmed());
        }
    }

    // Show closest matches
    if let Some(matches) = closest_matches {
        if !matches.is_empty() {
            eprintln!();
            eprintln!("      {}:", "Closest matches in file".dimmed());
            for m in matches.iter().take(3) {
                eprintln!();
                eprintln!(
                    "      {} Line {} ({}% similar):",
                    "│".dimmed(),
                    m.line.to_string().yellow(),
                    ((m.similarity * 100.0) as u32).to_string().yellow()
                );
                for line in m.content.lines().take(4) {
                    eprintln!("      {}   {}", "│".dimmed(), line);
                }
                if m.content.lines().count() > 4 {
                    eprintln!("      {}   {}", "│".dimmed(), "...".dimmed());
                }
            }
        }
    }

    // Show hint
    if let Some(h) = hint {
        eprintln!();
        eprintln!("      {} {}", "Hint:".cyan(), h);
    }
}

// NOTE(jimmylee)
// Prints the summary line to stderr.
pub fn print_summary(applied: usize, failed: usize) {
    eprintln!();
    eprintln!("{}", "━".repeat(50).dimmed());

    if failed == 0 {
        eprintln!(
            "{} {} applied, {} failed",
            "SUMMARY:".bold(),
            applied.to_string().green().bold(),
            failed.to_string().green()
        );
    } else {
        eprintln!(
            "{} {} applied, {} failed",
            "SUMMARY:".bold(),
            applied.to_string().yellow(),
            failed.to_string().red().bold()
        );
    }
}

// NOTE(jimmylee)
// Prints the final result as JSON to stdout.
pub fn print_json_result(result: &ApplyResult) {
    if let Ok(json) = serde_json::to_string_pretty(result) {
        println!("{}", json);
    } else {
        // Fallback to minimal JSON on serialization error
        println!(
            r#"{{"success": {}, "applied": {}, "failed": {}}}"#,
            result.success, result.applied, result.failed
        );
    }
}

// NOTE(jimmylee)
// Outputs result for a single edit based on outcome type.
pub fn print_edit_outcome(outcome: &EditOutcome, index: usize, total: usize) {
    match outcome {
        EditOutcome::Ok {
            path,
            edit_type,
            message,
            ..
        } => {
            let msg = message
                .as_ref()
                .map(|s| s.as_str())
                .unwrap_or("Success");
            print_edit_success(index, total, edit_type, path, msg);
        }
        EditOutcome::Warning {
            path,
            edit_type,
            warning,
            message,
            ..
        } => {
            print_edit_warning(index, total, edit_type, path, warning, message);
        }
        EditOutcome::Error {
            path,
            edit_type,
            message,
            search_preview,
            closest_matches,
            hint,
            ..
        } => {
            print_edit_error(
                index,
                total,
                edit_type,
                path,
                message,
                search_preview.as_deref(),
                closest_matches.as_ref(),
                hint.as_deref(),
            );
        }
    }
}

// NOTE(jimmylee)
// Prints header for read command output.
pub fn print_read_header(path: &str, lines: usize, bytes: usize) {
    eprintln!(
        "{} ({} lines, {} bytes)",
        path.bold().white(),
        lines.to_string().cyan(),
        format_bytes(bytes).cyan()
    );
}

// NOTE(jimmylee)
// Formats byte count as human-readable string.
fn format_bytes(bytes: usize) -> String {
    if bytes < 1024 {
        format!("{} B", bytes)
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    }
}

// NOTE(jimmylee)
// Prints an error message to stderr.
pub fn print_error(message: &str) {
    eprintln!("{} {}", "ERROR:".red().bold(), message);
}

// NOTE(jimmylee)
// Prints a warning message to stderr.
pub fn print_warning(message: &str) {
    eprintln!("{} {}", "WARNING:".yellow().bold(), message);
}

// NOTE(jimmylee)
// Flushes stderr to ensure all output is visible.
pub fn flush_stderr() {
    let _ = io::stderr().flush();
}
