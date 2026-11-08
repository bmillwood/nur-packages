{ lib
, python3Packages
, fetchFromGitHub

}:

let
  wenmode = python3Packages.callPackage ./wenmode { };
  quickjs-ng = python3Packages.callPackage ./quickjs-ng { };
in
python3Packages.buildPythonApplication rec {
  pname = "claude-code-log";
  version = "1.7.0"; # renovate: datasource=github-tags depName=daaain/claude-code-log
  pyproject = true;

  src = fetchFromGitHub {
    owner = "daaain";
    repo = "claude-code-log";
    tag = version;
    hash = "sha256-qeLpWVb96KxO38Yl4oYFfDgX5e+hRlToALRv08FtbqM=";
  };

  patches = [
    # Stored XSS through an embedded image's media_type, fixed upstream after
    # 1.7.0. Drop this once a release includes it.
    ./escape-image-data-urls.patch
  ];

  build-system = [ python3Packages.hatchling ];

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
  ]) ++ [
    wenmode
    quickjs-ng
  ];

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
