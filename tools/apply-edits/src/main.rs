// NOTE(jimmylee)
// CLI entry point for apply-edits tool.
// Provides subcommands for applying edits and reading files.

use apply_edits::edits::EditRequest;
use apply_edits::output::{
    flush_stderr, print_edit_outcome, print_error, print_header, print_json_result,
    print_processing_start, print_read_header, print_workdir,
};
use apply_edits::{read_files, format_files_for_prompt};
use clap::{Parser, Subcommand};
use std::io::{self, Read};
use std::path::PathBuf;

// NOTE(jimmylee)
// CLI argument structure using clap derive macros.
#[derive(Parser)]
#[command(name = "apply-edits")]
#[command(author = "www-agent")]
#[command(version)]
#[command(about = "Apply targeted code edits with multi-line support", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

// NOTE(jimmylee)
// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Apply edits from JSON input
    Apply {
        /// Path to JSON file containing edits
        #[arg(long, conflicts_with = "stdin")]
        file: Option<PathBuf>,

        /// Read JSON from stdin
        #[arg(long, conflicts_with = "file")]
        stdin: bool,

        /// Working directory (repository root)
        #[arg(long)]
        workdir: PathBuf,

        /// Dry-run mode: show what would happen without making changes
        #[arg(long)]
        dry_run: bool,

        /// Partial mode: continue applying remaining edits even if some fail (non-atomic)
        /// By default, edits are atomic - any failure rolls back all changes
        #[arg(long)]
        partial: bool,
    },

    /// Read files with line numbers
    Read {
        /// Single file to read
        #[arg(long, conflicts_with = "files")]
        file: Option<String>,

        /// Comma-separated list of files to read
        #[arg(long, conflicts_with = "file")]
        files: Option<String>,

        /// Working directory (repository root)
        #[arg(long)]
        workdir: PathBuf,

        /// Maximum lines to read per file
        #[arg(long, default_value = "500")]
        max_lines: usize,

        /// Output format (json or prompt)
        #[arg(long, default_value = "json")]
        format: String,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Apply { file, stdin, workdir, dry_run, partial } => {
            run_apply(file, stdin, workdir, dry_run, partial);
        }
        Commands::Read {
            file,
            files,
            workdir,
            max_lines,
            format,
        } => {
            run_read(file, files, workdir, max_lines, format);
        }
    }
}

// NOTE(jimmylee)
// Runs the apply subcommand.
fn run_apply(file: Option<PathBuf>, stdin: bool, workdir: PathBuf, dry_run: bool, partial: bool) {
    print_header();
    print_workdir(&workdir.display().to_string());

    if dry_run {
        eprintln!("🔍 DRY-RUN MODE: No files will be modified");
    }
    if partial {
        eprintln!("⚠️  PARTIAL MODE: Continuing on errors (non-atomic)");
    } else {
        eprintln!("🔒 ATOMIC MODE: Any failure will roll back all changes");
    }

    // Read JSON input
    let json_content = if stdin {
        let mut buffer = String::new();
        if let Err(e) = io::stdin().read_to_string(&mut buffer) {
            print_error(&format!("Failed to read from stdin: {}", e));
            std::process::exit(1);
        }
        buffer
    } else if let Some(path) = file {
        match std::fs::read_to_string(&path) {
            Ok(content) => content,
            Err(e) => {
                print_error(&format!("Failed to read file {}: {}", path.display(), e));
                std::process::exit(1);
            }
        }
    } else {
        print_error("Either --file or --stdin must be specified");
        std::process::exit(1);
    };

    // Parse JSON
    let request: EditRequest = match serde_json::from_str(&json_content) {
        Ok(r) => r,
        Err(e) => {
            print_error(&format!("Failed to parse JSON: {}", e));
            eprintln!();
            eprintln!("First 500 chars of input:");
            eprintln!("{}", &json_content.chars().take(500).collect::<String>());
            std::process::exit(1);
        }
    };

    // Apply edits
    let total = request.edits.len();
    print_processing_start(total);

    // NOTE(angeldev)
    // Use apply_edits_with_options to support dry-run and partial/atomic modes
    let result = apply_edits::apply_edits_with_options(&workdir, &request.edits, dry_run, partial);

    // Print human-readable output for each edit
    for (i, outcome) in result.edits.iter().enumerate() {
        print_edit_outcome(outcome, i, total);
    }

    // Print summary
    let mode_suffix = if dry_run { " (dry-run)" } else { "" };
    eprintln!();
    if result.success {
        eprintln!("✅ {} edit(s) applied{}, {} failed", result.applied, mode_suffix, result.failed);
    } else {
        eprintln!("❌ {} edit(s) applied{}, {} failed", result.applied, mode_suffix, result.failed);
        if !partial && result.failed > 0 {
            eprintln!("   All changes rolled back due to failure (atomic mode)");
        }
    }
    flush_stderr();

    // Print JSON result to stdout
    print_json_result(&result);

    // Exit with appropriate code
    if result.success {
        std::process::exit(0);
    } else {
        std::process::exit(1);
    }
}

// NOTE(jimmylee)
// Runs the read subcommand.
fn run_read(
    file: Option<String>,
    files: Option<String>,
    workdir: PathBuf,
    max_lines: usize,
    format: String,
) {
    // Build list of files to read
    let paths: Vec<String> = if let Some(f) = file {
        vec![f]
    } else if let Some(fs) = files {
        fs.split(',').map(|s| s.trim().to_string()).collect()
    } else {
        print_error("Either --file or --files must be specified");
        std::process::exit(1);
    };

    // Read files
    let results = read_files(&workdir, &paths, Some(max_lines));

    // Output based on format
    match format.as_str() {
        "json" => {
            // Print human info to stderr
            for file_result in &results.files {
                if file_result.exists {
                    print_read_header(
                        &file_result.path,
                        file_result.lines.unwrap_or(0),
                        file_result.bytes.unwrap_or(0),
                    );
                } else {
                    eprintln!("{} (does not exist)", file_result.path);
                }
            }

            // Print JSON to stdout
            if let Ok(json) = serde_json::to_string_pretty(&results) {
                println!("{}", json);
            }
        }
        "prompt" => {
            // Print formatted output suitable for LLM prompts
            let output = format_files_for_prompt(&results);
            print!("{}", output);
        }
        _ => {
            print_error(&format!("Unknown format: {}. Use 'json' or 'prompt'", format));
            std::process::exit(1);
        }
    }
}
