#!/usr/bin/env bash
# Builds the llm-wiki helper for release, and keeps helper.lock in step with it.
#
#   scripts/helper.sh hash            Print the hash of the helper's source.
#   scripts/helper.sh build DIR [P]   Build every platform into DIR, or only platform P.
#   scripts/helper.sh lock            Build, and write helper.lock from the result.
#   scripts/helper.sh check [DIR]     Build, and fail unless it matches helper.lock.
#
# helper.lock holds the SHA-256 of the helper for each platform, in the same commit as
# the source it was built from. `wiki update` downloads a helper only if it matches.
# That works because the build is reproducible: the same source, compiler and flags
# give the same bytes on any machine, in any folder. So the compiler is pinned (the
# lock names it) and the flags below leave out paths, build ids and version control.
# After changing anything under cmd/ or internal/, run `scripts/helper.sh lock` and
# commit helper.lock. CI runs `check`, then publishes what it built.
# Works with the bash that ships on macOS (3.2) and on Linux.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO/helper.lock"
PLATFORMS="darwin-arm64 darwin-amd64 linux-amd64 linux-arm64"
# What the bytes depend on besides the source and the compiler. A change here is a
# change to every binary, so it is part of the source hash.
FLAGS='-trimpath -buildvcs=false -ldflags=-s -w -buildid= CGO_ENABLED=0 GOAMD64=v1'

die() { echo "error: $*" >&2; exit 1; }

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi
}

# toolchain: the compiler the lock names, or the one here when there is no lock yet.
# To move to a newer compiler, change the lock's toolchain line and run lock again.
toolchain() {
  local t
  t="$(sed -n 's/^toolchain //p' "$LOCK" 2>/dev/null | head -n 1)"
  [ -n "$t" ] || t="$(go env GOVERSION)"
  printf '%s' "$t"
}

# source_hash: twelve hex digits over the compiler, the flags, go.mod and every Go file
# that goes into the binary. Tests don't, so a test can change without a new release.
source_hash() {
  local f
  {
    printf 'toolchain %s\nflags %s\n' "$(toolchain)" "$FLAGS"
    (
      cd "$REPO"
      sha256 go.mod
      find cmd internal -type f -name '*.go' ! -name '*_test.go' | LC_ALL=C sort | while IFS= read -r f; do sha256 "$f"; done
    )
  } | sha256 | cut -c 1-12
}

# build <dir> [platform]: the helper for each platform, as <dir>/llm-wiki-<platform>.
build() {
  local dir="$1" only="${2:-}" p
  command -v go >/dev/null 2>&1 || die "building the helper needs go"
  mkdir -p "$dir"
  for p in $PLATFORMS; do
    [ -z "$only" ] || [ "$only" = "$p" ] || continue
    GOTOOLCHAIN="$(toolchain)" GOOS="${p%-*}" GOARCH="${p#*-}" CGO_ENABLED=0 GOAMD64=v1 GOFLAGS='' \
      go build -C "$REPO" -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "$dir/llm-wiki-$p" ./cmd/llm-wiki \
      || die "the build for $p failed"
  done
}

# lock_text <dir>: what helper.lock should say for the binaries in dir.
lock_text() {
  local dir="$1" p
  cat <<EOF
# The released llm-wiki helper for this checkout: the compiler it is built with, a hash
# of its source, and the SHA-256 of the binary for each platform. \`wiki update\`
# downloads the helper and keeps it only if it matches. scripts/helper.sh writes this
# file: run \`scripts/helper.sh lock\` after changing anything under cmd/ or internal/.
toolchain $(toolchain)
source $(source_hash)
EOF
  for p in $PLATFORMS; do
    printf '%s %s\n' "$p" "$(sha256 "$dir/llm-wiki-$p" | cut -d ' ' -f 1)"
  done
}

cmd="${1:-}"
case "$cmd" in
  hash) source_hash; echo ;;
  build)
    [ $# -ge 2 ] || die "build needs a folder"
    build "$2" "${3:-}"
    ;;
  lock)
    tmp="$(mktemp -d)"
    build "$tmp"
    # Worked out before the file is opened for writing: the compiler's name comes from it.
    text="$(lock_text "$tmp")"
    printf '%s\n' "$text" > "$LOCK"
    echo "wrote $(basename "$LOCK"): source $(source_hash), built with $(toolchain)"
    ;;
  check)
    [ -f "$LOCK" ] || die "no helper.lock. Run: scripts/helper.sh lock"
    dir="${2:-$(mktemp -d)}"
    build "$dir"
    if [ "$(lock_text "$dir")" = "$(cat "$LOCK")" ]; then
      echo "helper.lock matches what this machine builds: source $(source_hash)"
    else
      echo "helper.lock does not match what this machine builds." >&2
      echo "Either the Go changed without \`scripts/helper.sh lock\`, or the build is not reproducible here." >&2
      lock_text "$dir" > "$dir/helper.lock.built"
      diff "$LOCK" "$dir/helper.lock.built" >&2 || true
      exit 1
    fi
    ;;
  *) die "usage: scripts/helper.sh hash | build DIR [PLATFORM] | lock | check [DIR]" ;;
esac
