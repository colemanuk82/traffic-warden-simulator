@echo off
rem Launches the Traffic Warden Sim prototype. Finds Godot 4.3+ or downloads it on first run.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\play.ps1"
if errorlevel 1 pause
