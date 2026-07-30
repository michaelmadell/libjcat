# Working notes: git history and building the distributables

## Applying patch 0006

```sh
cd /d/JCAT/libjcat
git am /c/Users/<you>/Downloads/0006-nsis-path-and-uninstall.patch
```

No rebuild needed — it only touches `contrib/win32/`.

---

## Git

### Where you are

Six commits on top of upstream `5fa45c2`:

```sh
git log --oneline 5fa45c2..HEAD
```

```
f48f7ee windows: make the installer's PATH and uninstall handling safe
e304480 windows: build without OpenPGP, and finish the SDK deliverable
e7d34de windows: do not hijack the gpgme installation directory
9a0ba1e windows: fix the two self test failures found on a real MSYS2 build
9f6c5f0 trivial: never translate line endings
a138f3a windows: make libjcat and jcat-tool build, run and package natively
```

### Put it on a branch and push

`git am` applied these to whatever branch you were on, probably `main`. Give
them a name and a remote:

```sh
git branch -m windows-port          # rename the current branch
git remote add fork https://github.com/<you>/libjcat.git
git push -u fork windows-port
```

Keep upstream reachable so you can rebase later:

```sh
git remote add upstream https://github.com/hughsie/libjcat.git
git fetch upstream
git rebase upstream/main             # replay the six commits onto new upstream
```

### Committing your own changes from here

```sh
git add -p                           # review hunk by hunk
git commit                           # subject line: "windows: <what changed>"
```

Upstream uses `area: Short description` subjects, present tense, with the *why*
in the body. `contrib/generate-version-script.py` is checked by
`jcat-exported-api`, so if you ever change the public API, regenerate:

```sh
meson compile -C build               # rewrites build/libjcat/jcat.map
cp build/libjcat/jcat.map libjcat/jcat.map
git commit libjcat/jcat.map -m "trivial: update the exported API"
```

### Splitting for upstream

Three of the six are not Windows-specific and will land far more easily on
their own. Cherry-pick them onto a clean branch:

```sh
git checkout -b fixes upstream/main
git cherry-pick 9f6c5f0              # .gitattributes / EOL translation
git cherry-pick 9a0ba1e              # python newline= fix (drop the meson hunk)
git push -u fork fixes
```

`9a0ba1e` also touched `libjcat/meson.build`; if you want only the Python fix
in that branch, `git cherry-pick -n` then unstage the meson hunk before
committing.

Leave the packaging work (`contrib/win32/`, `.github/workflows/windows.yml`) as
a separate PR — it is additive and reviewers treat it independently.

### Tagging your builds

```sh
git tag -a win-0.2.7-1 -m "Windows build 1 of libjcat 0.2.7"
git push fork win-0.2.7-1
```

Use a suffix like `-1`, `-2` so packaging-only rebuilds are distinguishable
from a libjcat version bump.

---

## Building the distributables

All commands run from the repo root in an **MSYS2 UCRT64** shell.

### 0. Configure once

```sh
meson setup build -Dgpg=false -Dman=false -Dgtkdoc=false --prefix="$MINGW_PREFIX"
```

Add `--wipe` to reconfigure an existing `build/`. `-Dgpg=false` is required;
see "OpenPGP is unsupported" in `contrib/win32/README.md`.

### 1. Build and test

```sh
meson compile -C build
XDG_DATA_HOME=/tmp/jcat-test-home meson test -C build --print-errorlogs
```

The `XDG_DATA_HOME` override keeps the test keyring out of your real
`%LOCALAPPDATA%`.

### 2. Standalone zip (+ SDK)

```sh
contrib/win32/bundle.sh build dist
```

Produces `dist/bin` (exe, DLLs), `dist/lib` (`libjcat.dll.a`, `jcat.pc`),
`dist/include/libjcat-1` (headers), `dist/share/licenses`.

Verify it from **cmd.exe**, not this shell:

```bat
set PATH=%SystemRoot%\system32;%SystemRoot%
cd /d D:\JCAT\libjcat
dist\bin\jcat-tool.exe --version
echo hello > firmware.bin
dist\bin\jcat-tool.exe --basename self-sign firmware.jcat firmware.bin --kind sha256
dist\bin\jcat-tool.exe info firmware.jcat
dist\bin\jcat-tool.exe --basename verify firmware.jcat firmware.bin --kind sha256
```

With the toolchain on PATH a missing DLL is masked by the copy in
`$MINGW_PREFIX/bin`, so this step is the only real test of the bundle.

Then zip it:

```sh
VERSION=$(meson introspect build --projectinfo | python -c 'import json,sys; print(json.load(sys.stdin)["version"])')
( cd dist && zip -r "../jcat-tool-${VERSION}-x86_64.zip" . )
```

### 3. NSIS installer

```sh
makensis -DVERSION="$VERSION" -DSRCDIR=../../dist contrib/win32/jcat-tool.nsi
```

`SRCDIR` and the output path are both relative to the `.nsi` file, so the
installer appears at
`contrib/win32/jcat-tool-<version>-x86_64-setup.exe`.

Before trusting the PATH component, dry-run the helper:

```sh
powershell -ExecutionPolicy Bypass -File contrib/win32/path-edit.ps1 \
  -Dir 'C:\Program Files\libjcat\bin' -Action Add -DryRun
```

Test the installer in a VM or with a throwaway `$INSTDIR` — it writes to HKLM
and edits the machine PATH. Silent install and uninstall:

```
jcat-tool-0.2.7-x86_64-setup.exe /S /D=C:\libjcat-test
C:\libjcat-test\Uninstall.exe /S
```

`/D=` must be last on the line and unquoted, even with spaces in the path.

### 4. MSYS2 package

```sh
cd contrib/win32
makepkg-mingw -sCLf
pacman -U mingw-w64-ucrt-x86_64-libjcat-*.pkg.tar.zst
cd ../..
```

Before submitting to `msys2/MINGW-packages`, replace the placeholder checksum:

```sh
cd contrib/win32 && updpkgsums && cd ../..
```

and set the `# Maintainer:` line to your name and address.

### 5. SDK check

Confirm a consumer can actually build against it:

```sh
PKG_CONFIG_PATH="$PWD/dist/lib/pkgconfig" pkg-config --cflags --libs jcat
```

Note the import library is MinGW format and cannot be linked from MSVC; that
needs a `.def`-generated import library.

---

## Clean rebuild from scratch

```sh
rm -rf build dist
meson setup build -Dgpg=false -Dman=false -Dgtkdoc=false
meson compile -C build
XDG_DATA_HOME=/tmp/jcat-test-home meson test -C build --print-errorlogs
contrib/win32/bundle.sh build dist
VERSION=$(meson introspect build --projectinfo | python -c 'import json,sys; print(json.load(sys.stdin)["version"])')
makensis -DVERSION="$VERSION" -DSRCDIR=../../dist contrib/win32/jcat-tool.nsi
```

## Gotcha worth remembering

MSYS2 rewrites Unix-looking arguments when calling native executables, so
`jcat-tool.exe --keyring /d/keys` arrives as `C:/msys64/d/keys`. Use Windows
paths, or prefix the command with `MSYS2_ARG_CONV_EXCL='*'`.
