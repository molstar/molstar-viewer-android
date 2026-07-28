#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
BASE_REF="${1:?Usage: verify-update-scope.sh <base-ref>}"
SCOPE_REPORT="${SCOPE_REPORT:-}"

git rev-parse --verify "$BASE_REF^{commit}" >/dev/null
mapfile -t changed < <(
  {
    git diff --name-only "$BASE_REF" --
    git ls-files --others --exclude-standard
  } | awk 'NF' | sort -u
)
((${#changed[@]} > 0)) || { echo "no update changes were found" >&2; exit 1; }

invalid=()
for path in "${changed[@]}"; do
  case "$path" in
    app/src/main/assets/viewer/vendor/molstar/*) ;;
    *) invalid+=("$path") ;;
  esac
done
if ((${#invalid[@]})); then
  printf 'Mol* automation changed files outside the upstream vendor boundary:\n' >&2
  printf '  %s\n' "${invalid[@]}" >&2
  exit 1
fi

# No whitespace lint here. Everything reaching this point is vendored upstream
# runtime, which is copied byte for byte and must not be reformatted, and the
# published bundle legitimately carries trailing whitespace.
printf '%s\n' "${changed[@]}"
if [[ -n "$SCOPE_REPORT" ]]; then
  mkdir -p "$(dirname "$SCOPE_REPORT")"
  printf '%s\n' "${changed[@]}" > "$SCOPE_REPORT"
fi
