; NSIS installer for jcat-tool.
;
; Build with:
;   makensis -DVERSION=0.2.7 -DSRCDIR=..\..\dist contrib\win32\jcat-tool.nsi
;
; SRCDIR must point at a directory produced by contrib/win32/bundle.sh.
;
; NOTE: use the NSIS "large strings" build if you enable the PATH component --
; the stock build truncates strings at 1024 chars and can corrupt a long PATH.

Unicode true
ManifestDPIAware true

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef SRCDIR
  !define SRCDIR "..\..\dist"
!endif

!define APPNAME "libjcat"
!define EXENAME "jcat-tool.exe"
!define PUBLISHER "The libjcat project"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME} ${VERSION}"
OutFile "jcat-tool-${VERSION}-x86_64-setup.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\${APPNAME}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "JSON Catalog Utility installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "LGPL-2.1-or-later"
VIAddVersionKey "CompanyName" "${PUBLISHER}"

!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"
!include "WinMessages.nsh"
!include "FileFunc.nsh"

!insertmacro GetSize

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_LICENSE "${SRCDIR}\share\licenses\libjcat\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "This build of ${APPNAME} requires 64-bit Windows."
    Abort
  ${EndIf}
  SetRegView 64
FunctionEnd

Section "Core files (required)" SecCore
  SectionIn RO
  SetOutPath "$INSTDIR"
  File /r "${SRCDIR}\*.*"

  ; kept for the uninstaller; see the PATH section below
  File "${__FILEDIR__}\path-edit.ps1"

  WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\${APPNAME}" "Version" "${VERSION}"

  ; Add/Remove Programs entry
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayName"     "${APPNAME} ${VERSION}"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr   HKLM "${UNINSTKEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayIcon"     "$INSTDIR\bin\${EXENAME}"
  WriteRegStr   HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr   HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegStr   HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKLM "${UNINSTKEY}" "URLInfoAbout"    "https://github.com/hughsie/libjcat"
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" "$0"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Add to system PATH" SecPath
  ; Delegated to PowerShell rather than done inline: NSIS truncates strings at
  ; 1024 chars in its default build, which silently corrupts a long PATH, and
  ; the value has to be read unexpanded so %SystemRoot% style entries survive.
  DetailPrint "Adding $INSTDIR\bin to the system PATH"
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" \
    -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$INSTDIR\path-edit.ps1" -Dir "$INSTDIR\bin" -Action Add'
  Pop $0
  ${If} $0 != 0
    DetailPrint "PATH update failed (exit $0); add $INSTDIR\bin manually"
  ${Else}
    ; tell running processes to re-read the environment
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}
SectionEnd

LangString DESC_SecCore ${LANG_ENGLISH} "jcat-tool.exe, libjcat and the required runtime libraries."
LangString DESC_SecPath ${LANG_ENGLISH} "Make jcat-tool runnable from any command prompt."
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecCore} $(DESC_SecCore)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecPath} $(DESC_SecPath)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetRegView 64

  ; remove ourselves from PATH before deleting the script that does it
  ${If} ${FileExists} "$INSTDIR\path-edit.ps1"
    nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" \
      -NoProfile -NonInteractive -ExecutionPolicy Bypass \
      -File "$INSTDIR\path-edit.ps1" -Dir "$INSTDIR\bin" -Action Remove'
    Pop $0
    ${If} $0 == 0
      SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
    ${EndIf}
  ${EndIf}

  ; Remove the whole install directory rather than a hardcoded list of
  ; subdirectories, which would silently leave behind anything added to the
  ; bundle later. Guarded on both the recorded install location and the
  ; presence of our own binary, so a mis-set $INSTDIR cannot delete something
  ; unrelated.
  ReadRegStr $1 HKLM "Software\${APPNAME}" "InstallDir"
  ${If} $1 == $INSTDIR
  ${AndIf} ${FileExists} "$INSTDIR\bin\${EXENAME}"
    RMDir /r "$INSTDIR"
  ${Else}
    MessageBox MB_ICONEXCLAMATION|MB_OK \
      "$INSTDIR does not look like a ${APPNAME} installation, so its contents \
       were left alone. Remove it by hand if you are sure."
    Delete "$INSTDIR\Uninstall.exe"
  ${EndIf}

  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\${APPNAME}"

  ; the keyring under %LOCALAPPDATA%\libjcat is user data, so leave it
SectionEnd
