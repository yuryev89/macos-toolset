#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 -m unittest discover -s Tests -v
python3 scripts/release.py metadata
swift run --package-path "$ROOT" --disable-sandbox CoreChecks
clang -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror -I "$ROOT/Sources/CSnapshot/include" "$ROOT/Sources/CSnapshot/snapshot.c" "$ROOT/scripts/native-smoke.c" -o "$ROOT/.build/native-smoke"
"$ROOT/.build/native-smoke"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx13.0" -I "$ROOT/.build/debug/Modules" -I "$ROOT/.build/debug/CSnapshot.build" "$ROOT/Sources/MacOSToolset/SystemServices.swift" "$ROOT/scripts/system-smoke.swift" "$ROOT/.build/debug/ToolsetCore.build/"*.o "$ROOT/.build/debug/CSnapshot.build/snapshot.c.o" -o "$ROOT/.build/system-smoke"
"$ROOT/.build/system-smoke"
