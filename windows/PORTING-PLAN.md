# Porting libjcat and jcat-tool to native Windows

Target: `jcat-tool.exe` plus `libjcat` runnable on a bare Windows machine, no
WSL, no MSYS2 installation required by the end user.

Baseline audited: upstream `hughsie/libjcat` at `5fa45c2` (2026-07-29, v0.2.7).

---

## Executive summary

This is not a rewrite. The library contains no POSIX-only code paths — no
`unistd.h`, no `fork`, no hardcoded `/etc` or `/usr` lookups at runtime, and the
keyring already lands in `%LOCALAPPDATA%` for free because it is derived from
`g_get_user_data_dir()`. Upstream even carries a MinGW cross file and a
Wine-based test script, though nothing in CI exercises them, so they had
bit-rotted.

The work is therefore: (1) a handful of real behavioural fixes that only bite
when the binary actually runs on Windows, (2) dependency and toolchain
provisioning, (3) packaging. Phase 1 and 2 below are **done and verified**;
phases 3–5 need a Windows machine or CI run to close out.

---

## Phase 1 — Code portability fixes ✅ done

All in the supplied patch. Each is a real defect, not a cosmetic change:

| Fix | Why it matters |
| --- | --- |
| Locale dir derived from module path | `JCAT_LOCALEDIR` baked in a Unix prefix at build time; a relocatable zip has no such path |
| `argv` from `g_win32_get_command_line()` | `main()`'s `argv` is in the ANSI codepage, so any filename outside CP-1252 arrives corrupted |
| `SetConsoleOutputCP(CP_UTF8)` | libjcat emits UTF-8; without this the console renders it as mojibake even though the bytes are right |
| `SetConsoleCtrlHandler` | Ctrl+C was a no-op on Windows because cancellation went through `g_unix_signal_add()` |
| gpgme `w32-inst-dir` | gpgme looks for `gpgme-w32spawn.exe` beside the *running executable*, which breaks whenever libjcat is loaded by a host app installed elsewhere |
| Bundled `gpg.exe` preferred | otherwise OpenPGP silently depends on the user having Gpg4win registered |
| No `--version-script` on PE | MinGW `ld` accepts the flag, then combining it with PE auto-export drops every symbol not listed — a silent ABI break |
| PE hardening flags | `-z relro`/`-z now` are ELF-only and were being silently discarded; replaced with ASLR/DEP/high-entropy-VA |
| `diff` optional | `find_program('diff')` was unconditional and hard-fails on a stock Windows box |
| Link `libintl` | `bindtextdomain()` is in a separate library on MinGW |
| VERSIONINFO + manifest | Explorer metadata, UTF-8 active code page, long-path awareness |
| `g_get_tmp_dir()` in self-test | hardcoded `/tmp/firmware.jcat` |

**Verified:** Linux build reconfigures, compiles with no new warnings, and both
tests (`jcat-self-test`, `jcat-exported-api`) pass with GPG + GnuTLS PKCS-7 +
ED25519 + introspection + VAPI all enabled. A sign/inspect round trip still
works. Zero regression.

## Phase 2 — Packaging machinery ✅ done

- `contrib/win32/mingw64-fedora.cross` — refreshed: wrong `cpu` value fixed,
  `windres` added (needed for the new resource), `pkgconfig` renamed to the
  modern `pkg-config` key, `needs_exe_wrapper` made explicit.
- `contrib/win32/mingw64-debian.cross` — new, with an honest warning that
  Debian packages no MinGW GLib stack.
- `contrib/win32/PKGBUILD` — MSYS2 package, suitable for submission to
  `msys2/MINGW-packages` (libjcat is currently absent from it).
- `contrib/win32/bundle.sh` — walks PE import tables recursively via `objdump
  -p`, copies non-system DLLs out of the toolchain prefix, ships licence texts.
  **Verified** against a purpose-built two-level DLL chain: it followed
  `jcat-tool.exe → libmid-1.dll → libleaf-1.dll` and correctly skipped
  `KERNEL32.dll` and `msvcrt.dll`.
- `contrib/win32/jcat-tool.nsi` — NSIS installer with Add/Remove Programs
  registration, optional PATH integration and a clean uninstall. **Verified**:
  compiles warning-free with `makensis 3.09`.
- `.github/workflows/windows.yml` — native MSYS2 build on `ucrt64` and
  `mingw64` plus a Fedora cross build. The important step is the bundle smoke
  test, which runs from `cmd.exe` with `PATH` reduced to `system32`: without
  that, a DLL missing from the bundle is masked by the toolchain copy and you
  ship a broken zip.

## Phase 3 — Land it on real hardware ⬜ next

1. Apply the patch, push the branch, let the `windows.yml` workflow run.
2. Expect fallout in roughly this order of likelihood:
   - **GnuTLS test certificate generation.** `data/tests/meson.build` invokes
     `certtool`; confirm the MSYS2 `gnutls` package ships `certtool.exe` and
     that the generated paths survive. If not, gate those test artefacts.
   - **The GPG self-test.** It spawns real `gpg.exe` in a temp home. Windows
     GnuPG is fussy about socket directories and homedir permissions; if it
     misbehaves, first check that `gpgme-w32spawn.exe` was bundled.
   - **Introspection/VAPI under MinGW.** Enabled in the PKGBUILD for
     completeness; if `g-ir-scanner` cannot run the generated helper, drop to
     `-Dintrospection=false` rather than fighting it — nothing in the CLI needs it.
3. Test with a non-ASCII filename (e.g. `firmware-Ω.bin`) and a path longer
   than 260 characters, since those are exactly what the manifest and argv
   changes exist for.
4. Confirm the keyring lands in `%LOCALAPPDATA%\libjcat` and that
   `--keyring` overrides it.

## Phase 4 — Ship the deliverables ⬜

- **Zip:** artefact of the CI bundle step; already produced.
- **Installer:** wire `makensis` output into a `release` job triggered on tags.
  Budget for code signing — an unsigned installer trips SmartScreen, and an EV
  certificate or an Azure Trusted Signing subscription is the only real fix.
- **MSYS2 package:** open a PR against `msys2/MINGW-packages` with the
  PKGBUILD, replacing `sha256sums=('SKIP')` with the real digest.
- **SDK:** already installed by `meson install` (`include/libjcat-1/`,
  `lib/libjcat.dll.a`, `lib/pkgconfig/jcat.pc`). Add these to the bundle if you
  want the zip to be developer-usable, and note that a MinGW `.dll.a` is not
  consumable from MSVC — that needs phase 5, or generating an import library
  from a `.def` with `dlltool`/`lib.exe`.
- Consider a `winget` manifest once the installer is signed.

## Phase 5 — MSVC / vcpkg ⬜ later

Wanted eventually, but it is a genuinely separate project because of one fact:
**vcpkg has no `gnutls` port.** `glib`, `json-glib`, `openssl`, `gpgme` and
`libgpg-error` all exist; GnuTLS does not.

libjcat already has an OpenSSL PKCS-7 backend (`-Dopenssl_pkcs7`), so PKCS-7 is
covered. But the ED25519 engine is GnuTLS-only, and ED25519 is what the binary
transparency verifier (`jcat-bt-verifier`, `jcat-bt-checkpoint`) is built on. An
MSVC build today would therefore ship a BT verifier that cannot verify.

The unblocking task is a new `libjcat/jcat-libcrypto-ed25519-engine.c` on
OpenSSL 3's `EVP_PKEY_ED25519`, mirroring the existing GnuTLS engine — on the
order of 200 lines, and worth upstreaming regardless of the MSVC question since
it also removes a GnuTLS dependency for OpenSSL-only distributions. Only after
that does `contrib/win32/vcpkg.json` become usable.

Secondary MSVC concerns, all tractable: the entire warning list in `meson.build`
is GCC syntax (Meson's `get_supported_arguments()` filters it, so you silently
lose all warnings — worth adding an MSVC-equivalent set), and symbol export
needs either `dllexport` annotations or a generated `.def`, since MSVC has no
auto-export.

---

## Risks worth naming up front

- **Nothing here has run on Windows yet.** Every claim above is verified on
  Linux or by static inspection of real PE binaries. Phase 3 is where the
  unknowns surface, and the GPG engine is the most likely to bite.
- **GnuPG on Windows is the weak link.** If OpenPGP turns into a time sink,
  `-Dgpg=false` removes it entirely and costs you only OpenPGP signatures;
  PKCS-7, ED25519 and checksums all keep working. Worth deciding early rather
  than late.
- **Upstreaming.** The portability fixes are individually defensible and belong
  upstream — split them into per-topic commits before opening a PR, since the
  single squashed commit supplied here is convenient for you but not reviewable.
  The packaging directory is more likely to be accepted as a separate change.
