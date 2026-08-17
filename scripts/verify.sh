#!/bin/zsh
# Deterministic local verification for Schiera.  This intentionally uses only
# tools supplied by macOS/Xcode; it does not download dependencies.
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"
export PATH

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
MODE="quick"
FAILED=0
TEMP_ROOT=""
DERIVED_DATA=""

usage() {
  cat <<'EOF'
Usage: scripts/verify.sh [--quick|--final|--help]

  --quick  Run repository checks and one isolated Debug build/test pass
           (default). Reports and PROGRESS.md are optional.
  --final  Require all task reports and PROGRESS.md, then run a second
           build/test pass with a newly created DerivedData directory.
  --help   Show this help and exit.
EOF
}

die_usage() { print -u2 "verify.sh: $1"; usage >&2; exit 2; }
case "${1:-}" in
  "") ;;
  --quick) MODE="quick" ;;
  --final) MODE="final" ;;
  --help|-h) usage; exit 0 ;;
  *) die_usage "unknown option: $1" ;;
esac

step() {
  local title="$1"
  shift
  print "\n== $title =="
  # Commands deliberately run without output filtering.  The if condition
  # makes errexit safe while preserving the command's exact exit status.
  if "$@"; then
    print "PASS: $title (exit 0)"
  else
    local exit_status=$?
    print -u2 "FAIL: $title (exit $exit_status)"
    FAILED=1
  fi
}

check_file() {
  local file_path="$1"
  [[ -f "$file_path" ]] || { print -u2 "missing file: ${file_path#$REPO_ROOT/}"; return 1; }
}

check_dir() {
  local dir_path="$1"
  [[ -d "$dir_path" ]] || { print -u2 "missing directory: ${dir_path#$REPO_ROOT/}"; return 1; }
}

check_structure() {
  check_file "$REPO_ROOT/Schiera.xcodeproj/project.pbxproj" || return 1
  check_dir "$REPO_ROOT/Sources/Schiera" || return 1
  check_dir "$REPO_ROOT/Tests/SchieraTests" || return 1
  check_dir "$REPO_ROOT/reports" || return 1
  check_file "$REPO_ROOT/README.md" || return 1
}

check_final_files() {
  local i report_path
  for i in {01..12}; do
    report_path="$REPO_ROOT/reports/TASK-${i}.md"
    check_file "$report_path" || return 1
  done
  check_file "$REPO_ROOT/PROGRESS.md" || return 1
}

check_readme() {
  local readme="$REPO_ROOT/README.md"
  check_file "$readme" || return 1
  local required=("Accessibility" "Build" "Test" "Supported" "Privacy" "Known limitations")
  local heading
  for heading in "${required[@]}"; do
    grep -Eqi -- "$heading" "$readme" || { print -u2 "README missing required section/content: $heading"; return 1; }
  done
}

check_project_references() {
  local project="$REPO_ROOT/Schiera.xcodeproj/project.pbxproj"
  check_file "$project" || return 1
  if grep -RInE -- "XCRemoteSwiftPackageReference|packageProductDependencies[[:space:]]*=[[:space:]]*\\([[:space:]]*[^)]|com\.apple\.security\.app-sandbox|ENABLE_APP_SANDBOX[[:space:]]*=[[:space:]]*YES" \
      "$project" "$REPO_ROOT/Sources" "$REPO_ROOT/Tests" 2>/dev/null; then
    print -u2 "forbidden package reference, network sandbox entitlement, or enabled app sandbox found"
    return 1
  fi
  # No package manifests or network entitlements may enter the repository.
  if find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -type f \( -name 'Package.swift' -o -name '*.entitlements' \) -print | while read -r file_path; do
    if [[ "$file_path" == *.entitlements ]] && grep -nEi -- "network\.client|network\.server|app-sandbox" "$file_path"; then
      print -u2 "forbidden entitlement in ${file_path#$REPO_ROOT/}"
      exit 1
    fi
    [[ "$file_path" == */Package.swift ]] && { print -u2 "Package.swift is not permitted: ${file_path#$REPO_ROOT/}"; exit 1; }
  done; then :; else return 1; fi
}

check_source_scan() {
  local source="$REPO_ROOT/Sources/Schiera"
  check_dir "$source" || return 1
  local patterns=(
    '(^|[[:space:]])import[[:space:]]+(Network|WebKit|Alamofire)'
    '\b(URLSession|URLRequest|NWConnection|NWPathMonitor)\b'
    '(Firebase|Amplitude|Mixpanel|Segment|Telemetry|AnalyticsSDK)'
    '(^|[^[:alnum:]_])_?CGS[A-Z][[:alnum:]_]*'
    '\b(TODO|FIXME|fatalError)[[:space:]]*[:(]'
    '\b(Mock|Fake|Stub|Placeholder|Simulation|Simulated)\b'
  )
  local pattern
  for pattern in "${patterns[@]}"; do
    if grep -RInE --include='*.swift' -- "$pattern" "$source"; then
      print -u2 "forbidden source pattern: $pattern"
      return 1
    fi
  done
}

check_public_scan() {
  local tracked
  tracked=( ${(f)"$(cd "$REPO_ROOT" && git ls-files -co --exclude-standard)"} )
  (( ${#tracked} > 0 )) || { print -u2 "git file list is empty"; return 1; }
  local file_path
  for file_path in "${tracked[@]}"; do
    [[ -f "$REPO_ROOT/$file_path" ]] || continue
    case "$file_path" in
      .DS_Store|*/.DS_Store|*/xcuserdata/*|*/DerivedData/*|*/build/*|*.xcresult/*) print -u2 "generated local metadata: $file_path"; return 1 ;;
    esac
  done
  local public_pattern='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{6,12}|com\.apple\.developer|/Users/[A-Za-z0-9._-]+/'
  local grep_status
  if (cd "$REPO_ROOT" && grep -RInIE --exclude-dir=.git --exclude-dir=xcuserdata -- "$public_pattern" .); then
    print -u2 "credential, signing/account identifier, or machine-specific home path found"
    return 1
  else
    grep_status=$?
    if (( grep_status != 1 )); then
      print -u2 "public repository scan failed (grep exit $grep_status)"
      return 1
    fi
  fi
}

make_derived_data() {
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/schiera-verify.XXXXXX")"
  [[ -n "$TEMP_ROOT" && "$TEMP_ROOT" != / && -d "$TEMP_ROOT" ]] || { print -u2 "unsafe temporary directory"; return 1; }
  DERIVED_DATA="$TEMP_ROOT/DerivedData"
  mkdir "$DERIVED_DATA"
  [[ -d "$DERIVED_DATA" && "$DERIVED_DATA" == "$TEMP_ROOT"/* ]] || { print -u2 "unsafe DerivedData path"; return 1; }
}

cleanup() {
  if [[ -n "$DERIVED_DATA" && -d "$DERIVED_DATA" && -n "$TEMP_ROOT" && "$DERIVED_DATA" == "$TEMP_ROOT"/* && "$DERIVED_DATA" != / ]]; then
    rm -rf -- "$DERIVED_DATA"
  fi
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" && "$TEMP_ROOT" != / ]]; then
    rmdir "$TEMP_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

print "Schiera verification ($MODE)"
step "Project and scheme listing" xcodebuild -project "$REPO_ROOT/Schiera.xcodeproj" -list
step "Project and property-list validation" zsh -c 'plutil -lint "$1/Schiera.xcodeproj/project.pbxproj" && while IFS= read -r p; do plutil -lint "$p"; done < <(find "$1" -path "$1/.git" -prune -o -type f -name "*.plist" -print)' zsh "$REPO_ROOT"
step "Repository structure" check_structure
if [[ "$MODE" == final ]]; then step "Task reports and PROGRESS.md" check_final_files; fi
step "README required sections" check_readme
step "Forbidden dependencies, entitlements, and project references" check_project_references
step "Source privacy/API/placeholder scan" check_source_scan
step "Public repository hygiene scan" check_public_scan

if make_derived_data; then
  step "Debug build (DerivedData: $DERIVED_DATA)" xcodebuild -project "$REPO_ROOT/Schiera.xcodeproj" -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED_DATA" build
  step "Unit tests (DerivedData: $DERIVED_DATA)" xcodebuild -project "$REPO_ROOT/Schiera.xcodeproj" -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED_DATA" test
else
  FAILED=1
fi

if [[ "$MODE" == final ]]; then
  # Dispose of the first isolated output before creating the independent
  # second pass, so final mode never leaves an earlier DerivedData tree.
  cleanup
  DERIVED_DATA=""
  TEMP_ROOT=""
  if make_derived_data; then
    step "Final second Debug build (fresh DerivedData: $DERIVED_DATA)" xcodebuild -project "$REPO_ROOT/Schiera.xcodeproj" -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED_DATA" build
    step "Final second unit-test pass (fresh DerivedData: $DERIVED_DATA)" xcodebuild -project "$REPO_ROOT/Schiera.xcodeproj" -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED_DATA" test
  else
    FAILED=1
  fi
fi

if (( FAILED == 0 )); then
  print "\nVERIFICATION PASSED ($MODE): repository checks, build, and tests completed successfully."
else
  print -u2 "\nVERIFICATION FAILED ($MODE): one or more checks failed; see the exact output above."
fi
exit "$FAILED"
