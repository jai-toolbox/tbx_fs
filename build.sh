#!/usr/bin/env bash
set -e

JAI_DIR="../../jai/bin"

case "$(uname -s)" in
  Linux*)
    JAI="$JAI_DIR/jai-linux"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    JAI="$JAI_DIR/jai.exe"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
esac

"$JAI" build.jai
