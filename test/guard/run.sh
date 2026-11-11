#!/bin/sh
# Kompiliert NoxisGuard gegen Android-Attrappen und führt die Logiktests aus (nur JDK nötig)
set -e
D="$(cd "$(dirname "$0")" && pwd)"
SRC="$D/../../vendor/noxis/packages/NoxisGuard/src"
OUT="$(mktemp -d)"
javac -nowarn -encoding UTF-8 -d "$OUT" $(find "$D/stubs" "$SRC" -name '*.java') "$D/FakeCtx.java" "$D/GuardTest.java"
java -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -cp "$OUT" com.noxis.guard.GuardTest
