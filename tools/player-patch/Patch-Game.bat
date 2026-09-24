@echo off
title Remains ModLoader - Game Patcher
echo ============================================
echo   Remains ModLoader - one-time game patch
echo   (run this ONCE; then drag mod packages in)
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_remains.ps1" %*
echo.
pause
