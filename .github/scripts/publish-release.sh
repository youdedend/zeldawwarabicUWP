#!/usr/bin/env bash
# Publishes this run's package assets to the shared Arabic Edition release.
# Every command is traced (set -x) and any failure surfaces in ::error::
# annotations with the exact command, thanks to the EXIT trap below.
set -euo pipefail
trace=$(mktemp)
exec 3>&1 4>&2   # keep the real stdout for the exit trap (annotations must reach the log)
exec >"$trace" 2>&1
set -x
trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tail -n 30 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[release] /"; fi' EXIT

TAG=${RELEASE_TAG:?}
REPO=${GITHUB_REPOSITORY:?}
TARGET=${GITHUB_REF_NAME:?}
TITLE=${RELEASE_TITLE:?}
ASSETS_DIR=${ASSETS_DIR:?}
[ "$#" -ge 1 ] || { echo "FATAL: no asset files given" >&2; exit 1; }

# Resolve the notes file to an absolute path before changing directory.
NOTES_ABS=$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")
[ -f "$NOTES_ABS" ] || { echo "FATAL: notes file missing: $NOTES_ABS" >&2; exit 1; }

# Optional canonical renames inside the asset directory (RENAME_FROM/RENAME_TO are space-separated lists).
read -ra REN_FROM <<< "${RENAME_FROM:-}"
read -ra REN_TO <<< "${RENAME_TO:-}"
[ "${#REN_FROM[@]}" = "${#REN_TO[@]}" ] || { echo "FATAL: RENAME_FROM/RENAME_TO length mismatch" >&2; exit 1; }

cd "$ASSETS_DIR"
echo "-- assets present --"
ls -la
for i in "${!REN_FROM[@]}"; do
    [ -f "${REN_FROM[$i]}" ] || { echo "FATAL: expected asset ${REN_FROM[$i]} not found in $ASSETS_DIR" >&2; exit 1; }
    mv "${REN_FROM[$i]}" "${REN_TO[$i]}"
done
for f in "$@"; do
    [ -f "$f" ] || { echo "FATAL: asset $f is missing after renames" >&2; exit 1; }
done

if ! gh release view "$TAG" --repo "$REPO" --json tagName -q .tagName > /dev/null 2>&1; then
    gh release create "$TAG" --repo "$REPO" --target "$TARGET" --title "$TITLE" --notes-file "$NOTES_ABS"
fi

uploaded=""
for attempt in 1 2 3 4 5; do
    if gh release upload "$TAG" "$@" --repo "$REPO" --clobber; then
        uploaded=1
        break
    fi
    echo "asset upload attempt $attempt failed; retrying in 20s"
    sleep 20
done
if [ -z "$uploaded" ]; then
    echo "FATAL: asset upload failed after 5 attempts" >&2
    exit 1
fi

gh release edit "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES_ABS"
echo "release $TAG is up to date"
