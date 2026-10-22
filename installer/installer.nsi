; Traffic Warden Sim installer (NSIS 3). Built by tools/build_release.sh:
;   makensis -DVERSION=1.0.0 -DSRC=<folder with TrafficWardenSim.exe> -DOUTFILE=<setup.exe> installer/installer.nsi

Unicode true
!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!define APPNAME "Traffic Warden Sim"
!define EXE "TrafficWardenSim.exe"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\TrafficWardenSim"

Name "${APPNAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "${UNINSTKEY}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "Traffic Warden Sim ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APPNAME} installer"
VIAddVersionKey "LegalCopyright" "colemanuk82"

!define MUI_ICON "${__FILEDIR__}/../tools/icon.ico"
!define MUI_UNICON "${__FILEDIR__}/../tools/icon.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}/welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}/welcome.bmp"
!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "Leaving already? The double yellows will miss you."

!define MUI_WELCOMEPAGE_TITLE "Welcome to the force, Warden!"
!define MUI_WELCOMEPAGE_TEXT "This will install ${APPNAME} ${VERSION} on your computer.$\r$\n$\r$\nTwelve streets full of dodgy parkers, three boss drivers, Halloween, Christmas Eve and a split-screen mode for you and a mate.$\r$\n$\r$\nClick Next to sign on for your first shift."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Uniform on. Ticket book ready."
!define MUI_FINISHPAGE_TEXT "${APPNAME} is installed. Off you go and write some tickets."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Start my first shift now"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Traffic Warden Sim (required)" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "${SRC}/${EXE}"
  File "${SRC}/README.txt"
  File "${SRC}/LilitaOne-OFL.txt"
  File "${SRC}/LuckiestGuy-LICENSE.txt"
  File "/oname=icon.ico" "${__FILEDIR__}/../tools/icon.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\icon.ico"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "colemanuk82"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\icon.ico"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "URLInfoAbout" "https://github.com/colemanuk82/traffic-warden-simulator"
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Desktop shortcut" SecDesktop
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\icon.ico"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "The game itself. Can't write tickets without it."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "Put a Traffic Warden Sim icon on your desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  Delete "$INSTDIR\${EXE}"
  Delete "$INSTDIR\README.txt"
  Delete "$INSTDIR\LilitaOne-OFL.txt"
  Delete "$INSTDIR\LuckiestGuy-LICENSE.txt"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$DESKTOP\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"
  DeleteRegKey HKLM "${UNINSTKEY}"
  ; Your save (career, wages, wardrobe) stays in %APPDATA%\Godot\app_userdata\Traffic Warden Sim
SectionEnd
