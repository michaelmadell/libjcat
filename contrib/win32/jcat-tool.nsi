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
!include "StrFunc.nsh"

; StrFunc requires each function to be declared before use
${StrLoc}
${UnStrRep}
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
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
  StrLen $1 $0
  ${If} $1 > 1000
    MessageBox MB_ICONEXCLAMATION|MB_OK \
      "Your system PATH is very long ($1 chars) so it was left unchanged, to \
       avoid truncating it.$\r$\nAdd $INSTDIR\bin manually if you want \
       jcat-tool on the PATH."
  ${Else}
    ; skip if some earlier install already added us
    ${StrLoc} $2 "$0" "$INSTDIR\bin" ">"
    ${If} $2 == ""
      WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" \
        "Path" "$0;$INSTDIR\bin"
      SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
    ${EndIf}
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
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
  ${UnStrRep} $1 "$0" ";$INSTDIR\bin" ""
  ${If} $1 != $0
    WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$1"
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}

  RMDir /r "$INSTDIR\bin"
  RMDir /r "$INSTDIR\share"
  RMDir /r "$INSTDIR\include"
  RMDir /r "$INSTDIR\lib"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\${APPNAME}"

  ; the keyring under %LOCALAPPDATA%\libjcat is user data, so leave it
SectionEnd
