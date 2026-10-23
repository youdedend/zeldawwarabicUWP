#!/usr/bin/env bash
# Publishes this run's package assets to the shared Arabic Edition release.
# Every gh invocation is traced (set -x) so a failure surfaces in the ::error::
# annotations with the exact command and error message.
set -euo pipefail
trace=$(mktemp)
exec 3>&1 4>&2   # keep the real stdout for the exit trap (annotations must reach the log)
exec >"$trace" 2>&1
set -x
trap 'status=$?; exec 1>&3 2>&4; cat "$trace"; if [ $status -ne 0 ]; then tail -n 30 "$trace" | tr "\n" "~" | fold -w 900 | sed "s/^/::error::[release] /"; fi' EXIT

TAG=${RELEASE_TAG:?}
REPO=${GITHUB_REPOSITORY:?}
NOTES=${NOTES_FILE:?}
TITLE=${RELEASE_TITLE:?}
TARGET=${GITHUB_REF_NAME:?}
[ "$#" -ge 1 ] || { echo "FATAL: no asset files given" >&2; exit 1; }
for f in "$@"; do
    [ -f "$f" ] || { echo "FATAL: asset $f is missing" >&2; exit 1; }
done

if ! gh release view "$TAG" --repo "$REPO" --json tagName -q .tagName > /dev/null 2>&1; then
    gh release create "$TAG" --repo "$REPO" --target "$TARGET" --title "$TITLE" --notes-file "$NOTES"
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

gh release edit "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES"
echo "release $TAG is up to date"
