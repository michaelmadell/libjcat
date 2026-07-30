#!/usr/bin/env bash
# Assemble a self-contained Windows distribution of jcat-tool.
#
# Walks the PE import tables of the built binaries and copies every DLL that
# resolves inside the toolchain prefix, recursively. System DLLs (kernel32,
# advapi32, ...) are left alone because they ship with Windows.
#
# Usage:
#   contrib/win32/bundle.sh <build-dir> <output-dir> [toolchain-prefix]
#
# Under MSYS2 the prefix defaults to $MINGW_PREFIX. When cross-compiling, pass
# it explicitly, e.g. /usr/x86_64-w64-mingw32/sys-root/mingw

set -euo pipefail

BUILD_DIR="${1:?usage: bundle.sh <build-dir> <output-dir> [prefix]}"
OUT_DIR="${2:?usage: bundle.sh <build-dir> <output-dir> [prefix]}"
PREFIX="${3:-${MINGW_PREFIX:-}}"

if [ -z "$PREFIX" ]; then
	echo "error: no toolchain prefix given and MINGW_PREFIX is unset" >&2
	exit 1
fi

OBJDUMP="${OBJDUMP:-objdump}"
command -v "$OBJDUMP" >/dev/null || { echo "error: $OBJDUMP not found" >&2; exit 1; }

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/share/licenses"

# --- collect the things we built ourselves -----------------------------------
shopt -s nullglob
built=("$BUILD_DIR"/libjcat/jcat-tool.exe "$BUILD_DIR"/libjcat/*.dll)
shopt -u nullglob
if [ ${#built[@]} -eq 0 ]; then
	echo "error: found no jcat-tool.exe or DLLs under $BUILD_DIR" >&2
	exit 1
fi
for f in "${built[@]}"; do
	install -m755 "$f" "$OUT_DIR/bin/"
done

# gpgme cannot spawn gpg without this helper, and looks for it beside the
# module that loaded it -- see jcat-gpg-engine.c. Only relevant when the build
# actually linked gpgme, so decide from the import tables rather than guessing.
if "$OBJDUMP" -p "$OUT_DIR"/bin/*.exe "$OUT_DIR"/bin/*.dll 2>/dev/null |
	grep -qi 'libgpgme'; then
	for helper in gpgme-w32spawn.exe gpg.exe gpgconf.exe; do
		if [ -f "$PREFIX/bin/$helper" ]; then
			install -m755 "$PREFIX/bin/$helper" "$OUT_DIR/bin/"
		else
			echo "note: $helper not found in $PREFIX/bin, OpenPGP may not work"
		fi
	done
else
	echo "note: built without gpgme, skipping the GnuPG helpers"
fi

# --- recursively resolve imports ---------------------------------------------
# associative array acts as the visited set, so diamond dependencies (nearly
# everything depends on libintl and libiconv) are only walked once
declare -A seen=()
queue=()
for f in "$OUT_DIR"/bin/*.exe "$OUT_DIR"/bin/*.dll; do
	[ -e "$f" ] || continue
	queue+=("$f")
done

while [ ${#queue[@]} -gt 0 ]; do
	current="${queue[0]}"
	queue=("${queue[@]:1}")

	# "DLL Name: libfoo-1.dll" lines from the PE import directory
	while read -r dll; do
		[ -n "$dll" ] || continue
		key="${dll,,}"
		[ -n "${seen[$key]:-}" ] && continue
		seen[$key]=1

		if [ -f "$PREFIX/bin/$dll" ]; then
			src="$PREFIX/bin/$dll"
		elif [ -f "$PREFIX/bin/${dll,,}" ]; then
			src="$PREFIX/bin/${dll,,}"
		else
			# not in our prefix, so it is a Windows system DLL
			continue
		fi

		if [ ! -f "$OUT_DIR/bin/$dll" ]; then
			install -m755 "$src" "$OUT_DIR/bin/$dll"
			echo "  bundled $dll"
		fi
		queue+=("$OUT_DIR/bin/$dll")
	done < <("$OBJDUMP" -p "$current" 2>/dev/null | sed -n 's/^\s*DLL Name:\s*//p')
done

# --- SDK: headers, import library, pkg-config -----------------------------------
# A MinGW .dll.a is not consumable from MSVC; a consumer there needs an import
# library generated from a .def. See PORTING-PLAN.md phase 5.
SRC_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -f "$BUILD_DIR/libjcat/libjcat.dll.a" ]; then
	install -Dm644 "$BUILD_DIR/libjcat/libjcat.dll.a" "$OUT_DIR/lib/libjcat.dll.a"

	# mirror meson's install layout: jcat.h at the include root, the rest
	# one level down under libjcat/. Read the list out of meson.build rather
	# than globbing, so internal engine headers are not shipped as API.
	install -Dm644 "$SRC_ROOT/libjcat/jcat.h" "$OUT_DIR/include/libjcat-1/jcat.h"
	sed -n '/^jcat_headers = files(/,/^)/p' "$SRC_ROOT/libjcat/meson.build" |
		grep -o "'[^']*\.h'" | tr -d "'" |
		while read -r h; do
			if [ -f "$SRC_ROOT/libjcat/$h" ]; then
				install -Dm644 "$SRC_ROOT/libjcat/$h" \
					"$OUT_DIR/include/libjcat-1/libjcat/$h"
			fi
		done
	# jcat-version.h is generated, so it lives in the build tree
	if [ -f "$BUILD_DIR/libjcat/jcat-version.h" ]; then
		install -Dm644 "$BUILD_DIR/libjcat/jcat-version.h" \
			"$OUT_DIR/include/libjcat-1/libjcat/jcat-version.h"
	fi

	# the generated .pc hardcodes the build prefix; make it relocatable so it
	# still resolves wherever the user unzips this
	pc=$(find "$BUILD_DIR" -name 'jcat.pc' -print -quit 2>/dev/null || true)
	if [ -n "$pc" ]; then
		mkdir -p "$OUT_DIR/lib/pkgconfig"
		sed 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$pc" \
			> "$OUT_DIR/lib/pkgconfig/jcat.pc"
	fi
	echo "  staged SDK (headers, import library, pkg-config)"
fi

# --- licence compliance -------------------------------------------------------
# LGPL and GPL components are being redistributed, so ship the texts
for d in "$PREFIX"/share/licenses/*; do
	[ -d "$d" ] || continue
	name=$(basename "$d")
	case " glib2 gnutls gpgme gnupg json-glib libiconv gettext nettle gmp libidn2 p11-kit libtasn1 zlib zstd brotli libunistring libgpg-error libassuan npth libffi pcre2 " in
		*" $name "*) cp -r "$d" "$OUT_DIR/share/licenses/" ;;
	esac
done
[ -f LICENSE ] && install -Dm644 LICENSE "$OUT_DIR/share/licenses/libjcat/LICENSE"

echo
echo "bundle ready: $OUT_DIR"
du -sh "$OUT_DIR"
find "$OUT_DIR/bin" -name '*.dll' | wc -l | xargs echo "DLLs bundled:"
