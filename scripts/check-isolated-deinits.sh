#!/bin/bash
# Fails if any class in a built app has a compiler-synthesized ISOLATED deinit.
#
# Under the project's MainActor-default settings, a main-actor class gets an
# isolated deinit unless it declares `nonisolated deinit {}`. On the iOS
# 26.0-26.3 runtime, releasing an instance of such a class aborts the app in
# swift_task_deinitOnExecutorImpl ("pointer being freed was not allocated").
# Tests on iOS 26.4+ and 27 can't see it, so this checks the binary instead:
# every isolated deinit leaves an `__isolated_deallocating_deinit` symbol.
#
# Usage: scripts/check-isolated-deinits.sh "path/to/Stack the Lineup.app"
set -euo pipefail

app="${1:?usage: $0 path/to/App.app}"

# Xcode-generated bundle-locator class; never deallocated.
allow='^ResourceBundleClass\.'

symbols=$(mktemp)
trap 'rm -f "$symbols"' EXIT

# Every Mach-O in the bundle (app, debug dylib, extensions). nm errors on
# non-Mach-O files are expected and skipped; at least one binary must scan.
scanned=0
while IFS= read -r -d '' f; do
  if nm "$f" >> "$symbols" 2>/dev/null; then scanned=$((scanned + 1)); fi
done < <(find "$app" -type f \( -name '*.dylib' -o -perm -u+x \) -print0)

if [ "$scanned" -eq 0 ]; then
  echo "error: no binaries could be scanned in $app"
  exit 2
fi

found=$(
  awk '{print $NF}' "$symbols" | grep -E 'fZ$' \
    | xcrun swift-demangle --simplified \
    | grep '__isolated_deallocating_deinit' \
    | grep -Ev "$allow" | sort -u || true
)

if [ -n "$found" ]; then
  echo "error: isolated deinits found (these crash on iOS 26.0-26.3 when released):"
  echo "$found" | sed 's/^/  /'
  echo "Add \`nonisolated deinit {}\` to each class; see AutoFillNLConstraintService."
  exit 1
fi
echo "No isolated deinits ($scanned binaries scanned)."
