# Building libjcat for Windows

Two supported toolchains. MinGW-w64 is the reference: it is the only one with a
complete feature set today.

## MinGW-w64 via MSYS2 (recommended)

Install [MSYS2](https://www.msys2.org/), then in a **UCRT64** shell:

```sh
pacman -S --needed \
  mingw-w64-ucrt-x86_64-{cc,meson,ninja,pkgconf,glib2,json-glib,gnutls,gpgme,gnupg} \
  diffutils

meson setup build -Dman=false -Dgtkdoc=false
meson compile -C build
meson test -C build
```

### Standalone redistributable

`meson install` places files inside the MSYS2 prefix, which is no use to anyone
who does not have MSYS2. To produce a directory that runs on a bare Windows
machine:

```sh
contrib/win32/bundle.sh build dist
```

This walks the PE import tables of the built binaries and copies every
non-system DLL out of `$MINGW_PREFIX`, recursively. Verify it by running
`dist\bin\jcat-tool.exe --version` from `cmd.exe` with a minimal `PATH` — if a
DLL is missing you will get a loader dialog rather than a silent fallback to the
toolchain copy.

### Installer

```sh
makensis -DVERSION=0.2.7 -DSRCDIR=../../dist contrib/win32/jcat-tool.nsi
```

Use the NSIS *large strings* build if you keep the PATH component; the stock
build truncates environment strings at 1024 characters.

### pacman package

`contrib/win32/PKGBUILD` builds an MSYS2 package:

```sh
cd contrib/win32 && makepkg-mingw -sCLf
pacman -U mingw-w64-ucrt-x86_64-libjcat-*.pkg.tar.zst
```

## Cross-compiling from Linux

```sh
meson setup build-win64 --cross-file contrib/win32/mingw64-fedora.cross \
  -Dgpg=false -Dintrospection=false -Dman=false
```

Fedora ships no `mingw64-gpgme`, so OpenPGP support is unavailable when
cross-compiling. Tests run under Wine if `WINEPATH` points at the MinGW `bin`
directory.

## Runtime notes

| Concern | Behaviour on Windows |
| --- | --- |
| Keyring location | `%LOCALAPPDATA%\libjcat` (from `g_get_user_data_dir()`), override with `--keyring` |
| GnuPG keyring | `%LOCALAPPDATA%\libjcat\gnupg` |
| `gpg.exe` | Taken from the install directory if bundled, otherwise gpgme's autodetection finds Gpg4win via the registry |
| `gpgme-w32spawn.exe` | Must sit beside `libjcat-1.dll`; `bundle.sh` and the PKGBUILD both install it |
| Non-ASCII paths | Handled: the exe manifest requests the UTF-8 active code page and argv comes from `g_win32_get_command_line()` |
| Long paths | `longPathAware` is set in the manifest, but also needs the machine-wide `LongPathsEnabled` policy |
| Ctrl+C | Cancels in-flight work through `SetConsoleCtrlHandler` |
