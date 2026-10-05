#!/usr/bin/env bash
set -euo pipefail

minimum="${1:-20}"
profile=".build/out/Products/Debug/codecov/default.profdata"
if [[ ! -f "$profile" ]]; then
  profile="$(find .build -path '*/debug/codecov/default.profdata' -print -quit)"
fi

if [[ -z "$profile" ]]; then
  echo "Coverage profile not found. Run: swift test --enable-code-coverage" >&2
  exit 1
fi

debug_dir="${profile%/codecov/default.profdata}"
binary="$debug_dir/PastryTests.xctest/Contents/MacOS/PastryTests"
if [[ ! -x "$binary" ]]; then
  binary="$debug_dir/PastryPackageTests.xctest/Contents/MacOS/PastryPackageTests"
fi

if [[ ! -x "$binary" ]]; then
  echo "Coverage test binary not found: $binary" >&2
  exit 1
fi

if ! summary="$(xcrun llvm-cov export \
  -summary-only \
  -format=text \
  "$binary" \
  -instr-profile "$profile" \
  -ignore-filename-regex='Tests|Sources/CSQLCipher|Version.generated.swift' 2>&1)"; then
  echo "$summary" >&2
  echo "Coverage data is stale. Run scripts/check_coverage.sh immediately after: swift test --enable-code-coverage" >&2
  exit 1
fi

coverage="$(
  SUMMARY_JSON="$summary" node -e '
    const data = JSON.parse(process.env.SUMMARY_JSON);
    const lines = data.data?.[0]?.totals?.lines;
    if (!lines || typeof lines.percent !== "number") process.exit(2);
    process.stdout.write(lines.percent.toFixed(2));
  '
)"

echo "Line coverage: ${coverage}% (minimum: ${minimum}%)"

awk -v coverage="$coverage" -v minimum="$minimum" 'BEGIN {
  if (coverage + 0 < minimum + 0) {
    printf("Coverage %.2f%% is below %.2f%%\n", coverage, minimum) > "/dev/stderr"
    exit 1
  }
}'
