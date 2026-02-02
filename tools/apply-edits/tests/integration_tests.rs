//! Integration tests for apply-edits tool.
//! Tests dry-run mode, atomic vs partial behavior, and JSON output compatibility.

use std::fs;
use std::process::Command;
use tempfile::tempdir;

/// Helper to run apply-edits with given JSON input
fn run_apply_edits(workdir: &std::path::Path, json_input: &str, args: &[&str]) -> std::process::Output {
    let cargo_bin = env!("CARGO_BIN_EXE_apply-edits");
    
    let mut cmd = Command::new(cargo_bin);
    cmd.arg("apply")
        .arg("--workdir")
        .arg(workdir)
        .arg("--stdin");
    
    for arg in args {
        cmd.arg(arg);
    }
    
    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    
    let mut child = cmd.spawn().expect("Failed to spawn apply-edits");
    
    use std::io::Write;
    child.stdin.take().unwrap().write_all(json_input.as_bytes()).unwrap();
    
    child.wait_with_output().expect("Failed to wait for apply-edits")
}

#[test]
fn test_dry_run_no_filesystem_changes() {
    let dir = tempdir().unwrap();
    let test_file = dir.path().join("test.txt");
    let original_content = "hello world\nline two\nline three\n";
    fs::write(&test_file, original_content).unwrap();
    
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "test.txt",
                "search": "hello world",
                "replace": "goodbye world"
            }
        ]
    }"#;
    
    let output = run_apply_edits(dir.path(), json_input, &["--dry-run"]);
    
    // Verify the command succeeded
    assert!(output.status.success(), "dry-run should succeed");
    
    // CRITICAL: Verify file was NOT modified
    let after_content = fs::read_to_string(&test_file).unwrap();
    assert_eq!(after_content, original_content, "dry-run should not modify files");
    
    // Verify stdout contains JSON with dry-run indication
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("\"success\": true"), "JSON should indicate success");
    
    // Verify stderr mentions dry-run
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("DRY-RUN") || stderr.contains("dry-run"), "stderr should mention dry-run mode");
}

#[test]
fn test_atomic_mode_rollback_on_failure() {
    let dir = tempdir().unwrap();
    
    // Create first file that will be modified successfully
    let file1 = dir.path().join("file1.txt");
    fs::write(&file1, "original content one\n").unwrap();
    
    // Create second file
    let file2 = dir.path().join("file2.txt");
    fs::write(&file2, "original content two\n").unwrap();
    
    // JSON with first edit succeeding, second failing (search not found)
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "file1.txt",
                "search": "original content one",
                "replace": "modified content one"
            },
            {
                "type": "replace",
                "path": "file2.txt",
                "search": "nonexistent string that will fail",
                "replace": "replacement"
            }
        ]
    }"#;
    
    // Run WITHOUT --partial (atomic mode is default)
    let output = run_apply_edits(dir.path(), json_input, &[]);
    
    // Command should fail
    assert!(!output.status.success(), "atomic mode should fail when any edit fails");
    
    // CRITICAL: First file should be rolled back to original
    let file1_content = fs::read_to_string(&file1).unwrap();
    assert_eq!(file1_content, "original content one\n", "file1 should be rolled back in atomic mode");
    
    // Second file should be unchanged
    let file2_content = fs::read_to_string(&file2).unwrap();
    assert_eq!(file2_content, "original content two\n", "file2 should be unchanged");
    
    // Verify stderr mentions rollback
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("rollback") || stderr.contains("Rollback") || stderr.contains("rolled back"),
        "stderr should mention rollback: {}", stderr);
}

#[test]
fn test_partial_mode_continues_on_failure() {
    let dir = tempdir().unwrap();
    
    let file1 = dir.path().join("file1.txt");
    fs::write(&file1, "original content one\n").unwrap();
    
    let file2 = dir.path().join("file2.txt");
    fs::write(&file2, "original content two\n").unwrap();
    
    // First edit succeeds, second fails, third should still run
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "file1.txt",
                "search": "original content one",
                "replace": "modified content one"
            },
            {
                "type": "replace",
                "path": "nonexistent.txt",
                "search": "anything",
                "replace": "replacement"
            },
            {
                "type": "replace",
                "path": "file2.txt",
                "search": "original content two",
                "replace": "modified content two"
            }
        ]
    }"#;
    
    // Run WITH --partial
    let output = run_apply_edits(dir.path(), json_input, &["--partial"]);
    
    // Command should fail (because one edit failed)
    assert!(!output.status.success(), "partial mode should still report failure");
    
    // First file SHOULD be modified (not rolled back)
    let file1_content = fs::read_to_string(&file1).unwrap();
    assert_eq!(file1_content, "modified content one\n", "file1 should be modified in partial mode");
    
    // Third edit should also have succeeded
    let file2_content = fs::read_to_string(&file2).unwrap();
    assert_eq!(file2_content, "modified content two\n", "file2 should be modified in partial mode");
    
    // Verify JSON output shows 2 applied, 1 failed
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("\"applied\": 2"), "should report 2 applied edits");
    assert!(stdout.contains("\"failed\": 1"), "should report 1 failed edit");
}

#[test]
fn test_json_output_schema_stability() {
    let dir = tempdir().unwrap();
    let test_file = dir.path().join("test.txt");
    fs::write(&test_file, "hello world\n").unwrap();
    
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "test.txt",
                "search": "hello world",
                "replace": "goodbye world"
            }
        ]
    }"#;
    
    let output = run_apply_edits(dir.path(), json_input, &[]);
    assert!(output.status.success());
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .expect("Output should be valid JSON");
    
    // Verify required top-level fields exist (backward compatibility)
    assert!(json.get("success").is_some(), "JSON must have 'success' field");
    assert!(json.get("applied").is_some(), "JSON must have 'applied' field");
    assert!(json.get("failed").is_some(), "JSON must have 'failed' field");
    assert!(json.get("edits").is_some(), "JSON must have 'edits' array");
    
    // Verify success is boolean
    assert!(json["success"].is_boolean(), "'success' must be boolean");
    
    // Verify applied/failed are numbers
    assert!(json["applied"].is_number(), "'applied' must be number");
    assert!(json["failed"].is_number(), "'failed' must be number");
    
    // Verify edits is array
    assert!(json["edits"].is_array(), "'edits' must be array");
    
    // Verify each edit outcome has required fields
    let edits = json["edits"].as_array().unwrap();
    for edit in edits {
        assert!(edit.get("status").is_some(), "Each edit must have 'status'");
        assert!(edit.get("index").is_some(), "Each edit must have 'index'");
        assert!(edit.get("path").is_some(), "Each edit must have 'path'");
        assert!(edit.get("type").is_some(), "Each edit must have 'type'");
    }
}

#[test]
fn test_json_output_error_schema() {
    let dir = tempdir().unwrap();
    let test_file = dir.path().join("test.txt");
    fs::write(&test_file, "hello world\n").unwrap();
    
    // This will fail - search string not found
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "test.txt",
                "search": "nonexistent string",
                "replace": "replacement"
            }
        ]
    }"#;
    
    let output = run_apply_edits(dir.path(), json_input, &["--partial"]);
    
    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout)
        .expect("Output should be valid JSON even on failure");
    
    // Verify error edit has expected fields
    let edits = json["edits"].as_array().unwrap();
    let error_edit = &edits[0];
    
    assert_eq!(error_edit["status"], "error", "Failed edit should have status 'error'");
    assert!(error_edit.get("error").is_some(), "Error edit must have 'error' field");
    assert!(error_edit.get("message").is_some(), "Error edit must have 'message' field");
    
    // These are optional but should be present for search_not_found errors
    assert!(error_edit.get("search_preview").is_some(), "search_not_found should have 'search_preview'");
    assert!(error_edit.get("closest_matches").is_some(), "search_not_found should have 'closest_matches'");
    assert!(error_edit.get("hint").is_some(), "search_not_found should have 'hint'");
}

#[test]
fn test_dry_run_validates_all_edits() {
    let dir = tempdir().unwrap();
    let test_file = dir.path().join("test.txt");
    fs::write(&test_file, "line one\nline two\nline three\n").unwrap();
    
    // Second edit will fail validation (search not found)
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "test.txt",
                "search": "line one",
                "replace": "LINE ONE"
            },
            {
                "type": "replace",
                "path": "test.txt",
                "search": "nonexistent",
                "replace": "replacement"
            }
        ]
    }"#;
    
    let output = run_apply_edits(dir.path(), json_input, &["--dry-run"]);
    
    // Should fail because second edit would fail
    assert!(!output.status.success(), "dry-run should fail if any edit would fail");
    
    // File should NOT be modified
    let content = fs::read_to_string(&test_file).unwrap();
    assert_eq!(content, "line one\nline two\nline three\n", "dry-run should not modify files even before failure");
    
    // JSON should show the failure
    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert_eq!(json["failed"], 1, "should report 1 failed edit");
}

#[test]
fn test_large_file_dry_run_no_modification() {
    let dir = tempdir().unwrap();
    let test_file = dir.path().join("large_file.txt");
    
    // Create a file larger than 100KB (the LARGE_FILE_THRESHOLD)
    let line = "This is a line of text that will be repeated many times to create a large file.\n";
    let large_content: String = line.repeat(2000); // ~160KB
    assert!(large_content.len() > 100 * 1024, "Test file must be >100KB");
    
    fs::write(&test_file, &large_content).unwrap();
    
    // Get original metadata for comparison
    let original_metadata = fs::metadata(&test_file).unwrap();
    let original_modified = original_metadata.modified().unwrap();
    
    // Small delay to ensure filesystem timestamp would change if modified
    std::thread::sleep(std::time::Duration::from_millis(50));
    
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "large_file.txt",
                "search": "This is a line of text",
                "replace": "This is MODIFIED text"
            }
        ]
    }"#;
    
    let output = run_apply_edits(dir.path(), json_input, &["--dry-run"]);
    
    // Should succeed in dry-run
    assert!(output.status.success(), "dry-run on large file should succeed");
    
    // CRITICAL: File content must be unchanged
    let after_content = fs::read_to_string(&test_file).unwrap();
    assert_eq!(after_content, large_content, "dry-run must not modify large file contents");
    
    // CRITICAL: File metadata (timestamp) should be unchanged
    let after_metadata = fs::metadata(&test_file).unwrap();
    let after_modified = after_metadata.modified().unwrap();
    assert_eq!(original_modified, after_modified, "dry-run must not change file modification time");
    
    // Verify JSON output indicates dry-run success
    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert!(json["success"].as_bool().unwrap(), "JSON should indicate success");
}

#[test]
fn test_atomic_rollback_multiple_files() {
    let dir = tempdir().unwrap();
    
    // Create three files that will be modified
    let file1 = dir.path().join("file1.txt");
    let file2 = dir.path().join("file2.txt");
    let file3 = dir.path().join("file3.txt");
    
    fs::write(&file1, "file1 original content\n").unwrap();
    fs::write(&file2, "file2 original content\n").unwrap();
    fs::write(&file3, "file3 original content\n").unwrap();
    
    // First two edits will succeed, third will fail (search not found)
    // This tests that ALL prior successful edits are rolled back
    let json_input = r#"{
        "edits": [
            {
                "type": "replace",
                "path": "file1.txt",
                "search": "file1 original content",
                "replace": "file1 MODIFIED content"
            },
            {
                "type": "replace",
                "path": "file2.txt",
                "search": "file2 original content",
                "replace": "file2 MODIFIED content"
            },
            {
                "type": "replace",
                "path": "file3.txt",
                "search": "this string does not exist and will cause failure",
                "replace": "replacement"
            }
        ]
    }"#;
    
    // Run in atomic mode (default, no --partial flag)
    let output = run_apply_edits(dir.path(), json_input, &[]);
    
    // Command should fail
    assert!(!output.status.success(), "atomic mode should fail when any edit fails");
    
    // CRITICAL: ALL files should be rolled back to original state
    let file1_content = fs::read_to_string(&file1).unwrap();
    let file2_content = fs::read_to_string(&file2).unwrap();
    let file3_content = fs::read_to_string(&file3).unwrap();
    
    assert_eq!(file1_content, "file1 original content\n", 
        "file1 must be rolled back in atomic mode");
    assert_eq!(file2_content, "file2 original content\n", 
        "file2 must be rolled back in atomic mode");
    assert_eq!(file3_content, "file3 original content\n", 
        "file3 should be unchanged (edit failed before modification)");
    
    // Verify stderr mentions rollback
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("rollback") || stderr.contains("Rollback") || stderr.contains("rolled back") || stderr.contains("Rolling back"),
        "stderr should mention rollback: {}", stderr);
    
    // Verify JSON output shows correct counts
    let stdout = String::from_utf8_lossy(&output.stdout);
    let json: serde_json::Value = serde_json::from_str(&stdout).unwrap();
    assert!(!json["success"].as_bool().unwrap(), "success should be false");
    assert_eq!(json["failed"], 1, "should report 1 failed edit");
}
