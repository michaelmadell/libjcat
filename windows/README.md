# Building libjcat for Windows

Two supported toolchains. MinGW-w64 is the reference: it is the only one with a
complete feature set today.

## MinGW-w64 via MSYS2 (recommended)

Install [MSYS2](https://www.msys2.org/), then in a **UCRT64** shell:

```sh
pacman -S --needed \
  mingw-w64-ucrt-x86_64-{cc,meson,ninja,pkgconf,glib2,json-glib,gnutls} \
  diffutils

meson setup build -Dgpg=false -Dman=false -Dgtkdoc=false
meson compile -C build
meson test -C build
```

`-Dgpg=false` is required for now; see "OpenPGP is unsupported" below.

### Standalone redistributable

`meson install` places files inside the MSYS2 prefix, which is no use to anyone
who does not have MSYS2. To produce a directory that runs on a bare Windows
machine:

```sh
contrib/win32/bundle.sh build dist
```

As well as the executable and its DLLs this stages the SDK -- the installed
headers, `libjcat.dll.a` and a relocated `jcat.pc`. Note that a MinGW import
library cannot be linked from MSVC; that needs a generated `.def`.

The DLL walk itself of the built binaries and copies every
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
| OpenPGP | Not built -- see below |
| Non-ASCII paths | Handled: the exe manifest requests the UTF-8 active code page and argv comes from `g_win32_get_command_line()` |
| Long paths | `longPathAware` is set in the manifest, but also needs the machine-wide `LongPathsEnabled` policy |
| Ctrl+C | Cancels in-flight work through `SetConsoleCtrlHandler` |

## Passing paths from an MSYS2 shell

MSYS2 rewrites arguments that look like Unix paths when it invokes a native
Windows executable, so `jcat-tool.exe --keyring /d/keys` arrives as
`C:/msys64/d/keys`. Pass Windows-style paths (`'D:\keys'`), or set
`MSYS2_ARG_CONV_EXCL='*'` to suppress the rewriting for one command. Quoting
does not help: the conversion happens at the msys/native boundary, not in the
shell. This also affects test selectors such as `-p '/jcat/engine{sha256}'`.

## OpenPGP is unsupported

Builds pass `-Dgpg=false`. PKCS-7, ED25519, the checksum engines and the binary
transparency verifier are all unaffected; only OpenPGP signatures are missing.

The blocker is below libjcat. `gpgme_op_import()` returns success having
considered zero keys: gpg is spawned with a correct argv and `--homedir`, the
input handle is translated into the child, gpgme writes the entire key into the
pipe (`_gpgme_io_write: leave: result=959`), and gpg then exits without writing
a byte to either its status fd or its logger fd. Because gpgme passes
`--exit-on-status-write-error`, that is what an unusable inherited handle looks
like from the outside, and the handle translation belongs to
`gpgme-w32spawn.exe`. The helper is installed and `CreateProcess` succeeds, so
the remaining suspect is the MSYS2 gpgme build configuring
`--disable-fd-passing`.

The same key imports fine when gpg is driven directly, including into a homedir
of the shape GLib's test isolation generates:

```sh
gpg --homedir 'D:\keys\gnupg' --import GPG-KEY-Linux-Vendor-Firmware-Service
```

`contrib/win32/gpgme-import-test.c` reproduces the failure in 90 lines with no
libjcat involved, for reporting upstream.
