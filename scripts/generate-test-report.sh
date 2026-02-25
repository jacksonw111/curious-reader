#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/dist/test-report"
XUNIT_XML="$REPORT_DIR/xunit.xml"
CONSOLE_LOG="$REPORT_DIR/console.txt"
HTML_REPORT="$REPORT_DIR/index.html"
REPORT_COVERAGE_JSON="$REPORT_DIR/codecov.json"

RUN_TESTS=1
if [[ "${1:-}" == "--reuse-existing" || "${1:-}" == "--no-test" ]]; then
  RUN_TESTS=0
elif [[ -n "${1:-}" && "${1:-}" != "--help" ]]; then
  echo "Unknown option: ${1}" >&2
  echo "Usage: $0 [--reuse-existing|--no-test]" >&2
  exit 1
fi

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [--reuse-existing|--no-test]"
  echo "  default: run swift test and generate report"
  echo "  --reuse-existing/--no-test: use existing xunit + coverage artifacts"
  exit 0
fi

mkdir -p "$REPORT_DIR"
mkdir -p "$ROOT_DIR/.build/clang-module-cache" "$ROOT_DIR/.build/xdg-cache"

# Sandbox-safe cache locations for SwiftPM/Clang.
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
export XDG_CACHE_HOME="$ROOT_DIR/.build/xdg-cache"
export HOME="$ROOT_DIR/.build/home"
mkdir -p "$HOME/.cache/clang/ModuleCache"

if [[ "$RUN_TESTS" -eq 1 ]]; then
  pushd "$ROOT_DIR" >/dev/null
  swift test --parallel --enable-code-coverage --xunit-output "$XUNIT_XML" | tee "$CONSOLE_LOG"
  popd >/dev/null
else
  if [[ ! -f "$XUNIT_XML" ]]; then
    echo "xUnit XML not found for reuse mode: $XUNIT_XML" >&2
    exit 1
  fi
  if [[ ! -s "$CONSOLE_LOG" ]]; then
    echo "Console log unavailable (reused existing test artifacts)." > "$CONSOLE_LOG"
  fi
fi

COVERAGE_JSON="$REPORT_COVERAGE_JSON"
if [[ ! -f "$COVERAGE_JSON" ]]; then
  COVERAGE_JSON="$ROOT_DIR/.build/arm64-apple-macosx/debug/codecov/CuriousReader.json"
fi
if [[ ! -f "$COVERAGE_JSON" ]]; then
  COVERAGE_JSON="$(find "$ROOT_DIR/.build" -type f -name 'CuriousReader.json' | head -n 1)"
fi

if [[ ! -f "$COVERAGE_JSON" ]]; then
  echo "Coverage JSON not found: $COVERAGE_JSON" >&2
  exit 1
fi

if [[ "$COVERAGE_JSON" != "$REPORT_COVERAGE_JSON" ]]; then
  cp "$COVERAGE_JSON" "$REPORT_COVERAGE_JSON"
  COVERAGE_JSON="$REPORT_COVERAGE_JSON"
fi

TOTAL_TESTS="$(xmllint --xpath 'string(sum(/testsuites/testsuite/@tests))' "$XUNIT_XML")"
TOTAL_FAILURES="$(xmllint --xpath 'string(sum(/testsuites/testsuite/@failures))' "$XUNIT_XML")"
TOTAL_ERRORS="$(xmllint --xpath 'string(sum(/testsuites/testsuite/@errors))' "$XUNIT_XML")"
TOTAL_TIME="$(xmllint --xpath 'string(sum(/testsuites/testsuite/@time))' "$XUNIT_XML")"

LINE_COVERAGE_RAW="$(jq -r '.data[0].totals.lines.percent' "$COVERAGE_JSON")"
FUNCTION_COVERAGE_RAW="$(jq -r '.data[0].totals.functions.percent' "$COVERAGE_JSON")"
LINES_COVERED="$(jq -r '.data[0].totals.lines.covered' "$COVERAGE_JSON")"
LINES_TOTAL="$(jq -r '.data[0].totals.lines.count' "$COVERAGE_JSON")"

LINE_COVERAGE="$(printf "%.2f" "$LINE_COVERAGE_RAW")"
FUNCTION_COVERAGE="$(printf "%.2f" "$FUNCTION_COVERAGE_RAW")"

if [[ "$TOTAL_FAILURES" == "0" && "$TOTAL_ERRORS" == "0" ]]; then
  STATUS_TEXT="PASS"
  STATUS_COLOR="#1d9a52"
else
  STATUS_TEXT="FAIL"
  STATUS_COLOR="#c23b22"
fi

MODULE_ROWS="$(
  awk -F'"' '
    /<testcase / {
      split($2, parts, ".");
      module = parts[1];
      count[module] += 1;
      duration[module] += $6;
    }
    END {
      for (module in count) {
        printf "<tr><td>%s</td><td>%d</td><td>%.3fs</td></tr>\n", module, count[module], duration[module];
      }
    }
  ' "$XUNIT_XML" | sort
)"

LOW_COVERAGE_ROWS="$(
  jq -r '
    .data[0].files[]
    | select(.summary.lines.count > 0)
    | [.filename, .summary.lines.percent, .summary.lines.covered, .summary.lines.count]
    | @tsv
  ' "$COVERAGE_JSON" \
  | sort -t $'\t' -k2,2n \
  | head -n 20 \
  | awk -F'\t' '
      {
        printf "<tr><td><code>%s</code></td><td>%.2f%%</td><td>%s / %s</td></tr>\n", $1, $2, $3, $4;
      }
    '
)"

GENERATED_AT="$(date "+%Y-%m-%d %H:%M:%S %Z")"

cat > "$HTML_REPORT" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Curious Reader Test Report</title>
  <style>
    :root {
      --bg: #f5f7fb;
      --card: #ffffff;
      --text: #1f2937;
      --muted: #6b7280;
      --border: #e5e7eb;
    }
    body {
      margin: 0;
      background: linear-gradient(180deg, #f8fafc 0%, #eef2ff 100%);
      color: var(--text);
      font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    }
    .container {
      max-width: 1120px;
      margin: 24px auto 48px;
      padding: 0 16px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: 0 6px 18px rgba(15, 23, 42, 0.06);
      padding: 16px;
      margin-bottom: 14px;
    }
    h1 {
      margin: 0 0 8px;
      font-size: 24px;
    }
    h2 {
      margin: 0 0 10px;
      font-size: 18px;
    }
    .muted { color: var(--muted); }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap: 10px;
      margin-top: 10px;
    }
    .metric {
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 10px;
      background: #fcfdff;
    }
    .metric .label {
      color: var(--muted);
      font-size: 12px;
    }
    .metric .value {
      margin-top: 2px;
      font-size: 20px;
      font-weight: 600;
    }
    .status {
      display: inline-block;
      padding: 3px 10px;
      border-radius: 999px;
      font-weight: 600;
      color: white;
      background: ${STATUS_COLOR};
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      text-align: left;
      padding: 8px 10px;
      border-bottom: 1px solid var(--border);
      vertical-align: top;
    }
    th {
      color: var(--muted);
      font-weight: 600;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.02em;
    }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
    a { color: #2563eb; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <div class="container">
    <div class="card">
      <h1>Curious Reader Test Report</h1>
      <div class="muted">Generated at ${GENERATED_AT}</div>
      <div style="margin-top:8px;"><span class="status">${STATUS_TEXT}</span></div>
      <div class="grid">
        <div class="metric"><div class="label">Tests</div><div class="value">${TOTAL_TESTS}</div></div>
        <div class="metric"><div class="label">Failures</div><div class="value">${TOTAL_FAILURES}</div></div>
        <div class="metric"><div class="label">Errors</div><div class="value">${TOTAL_ERRORS}</div></div>
        <div class="metric"><div class="label">Duration</div><div class="value">${TOTAL_TIME}s</div></div>
        <div class="metric"><div class="label">Line Coverage</div><div class="value">${LINE_COVERAGE}%</div></div>
        <div class="metric"><div class="label">Function Coverage</div><div class="value">${FUNCTION_COVERAGE}%</div></div>
      </div>
      <div class="muted" style="margin-top:8px;">Lines covered: ${LINES_COVERED} / ${LINES_TOTAL}</div>
      <div style="margin-top:10px;">
        <a href="./xunit.xml">xUnit XML</a> |
        <a href="./codecov.json">Coverage JSON</a> |
        <a href="./console.txt">Console Log</a>
      </div>
    </div>

    <div class="card">
      <h2>Tests By Module</h2>
      <table>
        <thead>
          <tr><th>Module</th><th>Test Count</th><th>Total Time</th></tr>
        </thead>
        <tbody>
          ${MODULE_ROWS}
        </tbody>
      </table>
    </div>

    <div class="card">
      <h2>Lowest Line Coverage Files (Top 20)</h2>
      <table>
        <thead>
          <tr><th>File</th><th>Line Coverage</th><th>Covered / Total</th></tr>
        </thead>
        <tbody>
          ${LOW_COVERAGE_ROWS}
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>
EOF

echo "HTML report generated at: $HTML_REPORT"
