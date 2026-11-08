{ lib
, buildPythonPackage
, fetchPypi
, hatchling
}:

buildPythonPackage rec {
  pname = "wenmode";
  # Kept in step with claude-code-log's version range, so no renovate comment.
  version = "0.15.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-/9kwJFkxsbA0bXtuFRrYTCHZe5FFwhnk1/oHmBaRKC8=";
  };

  build-system = [ hatchling ];

  pythonImportsCheck = [ "wenmode" ];

  meta = {
    description = "Fast, composable Markdown parser and renderer toolkit";
    homepage = "https://wenmode.lepture.com";
    license = lib.licenses.bsd3;
  };
}
