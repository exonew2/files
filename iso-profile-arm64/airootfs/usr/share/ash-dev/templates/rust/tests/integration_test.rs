use assert_cmd::Command;

#[test]
fn test_cli_help() {
    let mut cmd = Command::cargo_bin("{{project_name}}").unwrap();
    cmd.arg("--help").assert().success();
}
