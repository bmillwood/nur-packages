{ lib
, python3Packages
, fetchFromGitHub
, gitMinimal

}:

let
  wenmode = python3Packages.callPackage ./wenmode { };
  quickjs-ng = python3Packages.callPackage ./quickjs-ng { };
in
python3Packages.buildPythonApplication rec {
  pname = "claude-code-log";
  version = "1.8.0"; # renovate: datasource=github-tags depName=daaain/claude-code-log
  pyproject = true;

  src = fetchFromGitHub {
    owner = "daaain";
    repo = "claude-code-log";
    tag = version;
    hash = "sha256-S3XPcvPdawk3C+Ecx3o2jQcEXm8Wt6BVsUCRTdaAeJI=";
  };

  build-system = [ python3Packages.hatchling ];

  # Upstream raised the floor to 3.2.1 for advisories in GitPython APIs that
  # claude-code-log doesn't use (daaain/claude-code-log#372). Drop this once
  # nixpkgs has 3.2.1.
  pythonRelaxDeps = [ "gitpython" ];

  dependencies = (with python3Packages; [
    click
    dateparser
    pydantic
    jinja2
    toml
    textual
    packaging
    gitpython
    pygments
    pyyaml
  ]) ++ [
    wenmode
    quickjs-ng
  ];

  # Commit links come from running git on the transcript's working directory,
  # and are quietly left out if it isn't on PATH.
  makeWrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ gitMinimal ]) ];

  pythonImportsCheck = [ "claude_code_log" ];

  # The upstream test suite needs Playwright and an in-repo test plugin, so
  # instead check the installed command can render real transcripts, which
  # catches missing dependencies and templates that weren't installed.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    for t in representative_messages hook_attachments; do
      $out/bin/claude-code-log test/test_data/$t.jsonl -o $HOME/$t.html
      grep -q '</html>' $HOME/$t.html
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "Convert Claude Code transcript JSONL files into readable HTML and Markdown";
    homepage = "https://github.com/daaain/claude-code-log";
    changelog = "https://github.com/daaain/claude-code-log/blob/${src.tag}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "claude-code-log";
  };
}
