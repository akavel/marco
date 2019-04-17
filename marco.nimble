# Package

version       = "0.1.0"
author        = "Mateusz Czapli\xC5\x84ski"
description   = "Manifests & resources compiler for .apk files"
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["marco"]


# Dependencies

requires "nim >= 0.19.4"
requires "xmltools 0.1.5"
requires "nimfp"
