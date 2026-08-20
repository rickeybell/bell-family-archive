@echo off
title Bell Family Archive Website Updater
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-BellWebsite.ps1"
