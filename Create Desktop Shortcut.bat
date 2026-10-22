@echo off
rem Puts a "Traffic Warden Sim" shortcut on your desktop. Run it once.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d = [Environment]::GetFolderPath('Desktop'); $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $d 'Traffic Warden Sim.lnk')); $s.TargetPath = '%~dp0Play Traffic Warden.bat'; $s.WorkingDirectory = '%~dp0'; $s.IconLocation = '%~dp0tools\icon.ico'; $s.Description = 'Play the Traffic Warden Sim prototype'; $s.Save(); Write-Host 'Shortcut added to your desktop.'"
pause
