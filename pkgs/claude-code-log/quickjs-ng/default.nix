{ lib
, buildPythonPackage
, fetchFromGitHub
, setuptools
, pyprojectVersionPatchHook
}:

let
  # Upstream's release CI checks out this tag of quickjs-ng in place of the
  # submodule commit the repo pins, and builds the published wheels from it.
  upstreamQuickjs = fetchFromGitHub {
    owner = "quickjs-ng";
    repo = "quickjs";
    tag = "v0.15.1";
    hash = "sha256-d52EFtBrOO6+DG93R+aWVUisX7SSk2eYLKhWWqX/lII=";
  };
in
buildPythonPackage rec {
  pname = "quickjs-ng";
  # Kept in step with claude-code-log's version range, so no renovate comment.
  version = "0.15.1.1";
  pyproject = true;

  # Not the PyPI sdist, because it leaves out quickjs-c-atomics.h.
  src = fetchFromGitHub {
    owner = "genotrance";
    repo = "quickjs-ng";
    tag = "v${version}";
    hash = "sha256-1kmBzeEkx1xQWK+LJzigj5n3TAmw71S26WJXBSLixRk=";
  };

  postUnpack = ''
    rmdir $sourceRoot/upstream-quickjs
    cp -r ${upstreamQuickjs} $sourceRoot/upstream-quickjs
    chmod -R u+w $sourceRoot/upstream-quickjs
  '';

  # pyproject.toml in the repo has a stale version. Release CI sets it from
  # the tag, so do the same.
  nativeBuildInputs = [ pyprojectVersionPatchHook ];

  build-system = [ setuptools ];

  pythonImportsCheck = [ "quickjs" ];

  meta = {
    description = "Thin Python wrapper of quickjs-ng";
    homepage = "https://github.com/genotrance/quickjs-ng";
    license = lib.licenses.mit;
  };
}
