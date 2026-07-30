#!/usr/bin/env bash
# Build the MSYS2 package from the current git checkout instead of an upstream
# release tarball.
#
# The PKGBUILD's source= is an upstream URL, which is right for submission to
# msys2/MINGW-packages but wrong for local use: it would build a libjcat with
# none of the Windows work in it. makepkg skips the download when the expected
# filename is already present, so stage one from git HEAD first.
#
# Usage: contrib/win32/makepkg-local.sh [extra makepkg args]

set -euo pipefail

SRC_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SRC_ROOT"

PKGVER=$(sed -n 's/^pkgver=//p' contrib/win32/PKGBUILD)
if [ -z "$PKGVER" ]; then
	echo "error: cannot read pkgver from contrib/win32/PKGBUILD" >&2
	exit 1
fi

# git archive exports HEAD, so anything uncommitted is silently absent from the
# package -- which is a confusing way to spend an afternoon
if ! git diff --quiet HEAD 2>/dev/null; then
	echo "WARNING: you have uncommitted changes; they will NOT be in the package."
	echo "         commit or stash them first if that is not what you want."
	echo
fi

TARBALL="contrib/win32/libjcat-${PKGVER}.tar.gz"
echo "==> staging $TARBALL from $(git rev-parse --short HEAD)"
git archive --format=tar.gz --prefix="libjcat-${PKGVER}/" -o "$TARBALL" HEAD

cd contrib/win32
echo "==> makepkg-mingw"
makepkg-mingw -sCLf "$@"

echo
echo "install with:"
echo "  pacman -U contrib/win32/${MINGW_PACKAGE_PREFIX:-mingw-w64-ucrt-x86_64}-libjcat-*.pkg.tar.zst"
