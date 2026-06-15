@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "REPO_URL=https://github.com/KOBOSHISME/WoW_Experimental_Playground.git"
set "REPO_BRANCH=main"
set "ADDON_FOLDER=WoW_Experimental_Playground"

if /I "%~1"=="--help" goto :Help
if /I "%~1"=="-h" goto :Help
if /I "%~1"=="/?" goto :Help

echo WoW Experimental Playground installer
echo.

call :EnsureGit
if errorlevel 1 goto :Fail

call :FindAddOns "%~1"
if errorlevel 1 goto :NoAddOns

set "TARGET_DIR=%ADDONS_DIR%\%ADDON_FOLDER%"

echo AddOns folder: "%ADDONS_DIR%"
echo Addon folder:  "%TARGET_DIR%"
echo.

if exist "%TARGET_DIR%\.git" (
    echo Existing git checkout found. Overwriting local changes...
    git -C "%TARGET_DIR%" remote set-url origin "%REPO_URL%"
    if errorlevel 1 goto :Fail
    git -C "%TARGET_DIR%" fetch --prune origin
    if errorlevel 1 goto :Fail
    git -C "%TARGET_DIR%" checkout -B "%REPO_BRANCH%" "origin/%REPO_BRANCH%"
    if errorlevel 1 goto :Fail
    git -C "%TARGET_DIR%" reset --hard "origin/%REPO_BRANCH%"
    if errorlevel 1 goto :Fail
    git -C "%TARGET_DIR%" clean -fdx
    if errorlevel 1 goto :Fail
) else (
    if exist "%TARGET_DIR%\" (
        echo Removing existing non-git addon folder...
        call :CheckTargetSafe
        if errorlevel 1 goto :Fail
        rmdir /s /q "%TARGET_DIR%"
        if exist "%TARGET_DIR%\" goto :Fail
    )

    echo Cloning addon...
    git clone --branch "%REPO_BRANCH%" "%REPO_URL%" "%TARGET_DIR%"
    if errorlevel 1 goto :Fail
)

echo.
echo Done. Restart WoW if it was open, then enable WoW Experimental Playground from the AddOns menu.
exit /b 0

:EnsureGit
where git.exe >nul 2>nul
if not errorlevel 1 exit /b 0

echo Git was not found. Installing Git for Windows with winget...
where winget.exe >nul 2>nul
if errorlevel 1 (
    echo winget was not found. Install Git for Windows, then run this file again:
    echo https://git-scm.com/download/win
    exit /b 1
)

winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 exit /b 1

set "PATH=%ProgramFiles%\Git\cmd;%ProgramFiles(x86)%\Git\cmd;%LOCALAPPDATA%\Programs\Git\cmd;%PATH%"
where git.exe >nul 2>nul
if errorlevel 1 (
    echo Git installed, but git.exe was not found on PATH yet. Close this window and run this file again.
    exit /b 1
)

exit /b 0

:FindAddOns
set "ADDONS_DIR="

if not "%~1"=="" (
    call :TryAddOns "%~1"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%~1\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%~1\_classic_era_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%~1\_classic_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    exit /b 1
)

call :TryAddOns "%ProgramFiles(x86)%\World of Warcraft\_classic_era_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0
call :TryAddOns "%ProgramFiles%\World of Warcraft\_classic_era_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0
call :TryAddOns "%ProgramFiles(x86)%\World of Warcraft\_classic_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0
call :TryAddOns "%ProgramFiles%\World of Warcraft\_classic_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0
call :TryAddOns "%PUBLIC%\Games\World of Warcraft\_classic_era_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0
call :TryAddOns "%PUBLIC%\Games\World of Warcraft\_classic_\Interface\AddOns"
if defined ADDONS_DIR exit /b 0

for %%D in (C D E F G H) do (
    call :TryAddOns "%%D:\World of Warcraft\_classic_era_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%%D:\World of Warcraft\_classic_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%%D:\Games\World of Warcraft\_classic_era_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
    call :TryAddOns "%%D:\Games\World of Warcraft\_classic_\Interface\AddOns"
    if defined ADDONS_DIR exit /b 0
)

exit /b 1

:TryAddOns
if "%~1"=="" exit /b 1
if not exist "%~1\." exit /b 1

for %%I in ("%~1") do (
    if /I not "%%~nxI"=="AddOns" exit /b 1
    set "ADDONS_DIR=%%~fI"
)

exit /b 0

:CheckTargetSafe
if "%ADDONS_DIR%"=="" exit /b 1
if "%TARGET_DIR%"=="" exit /b 1
if /I "%TARGET_DIR%"=="%ADDONS_DIR%" exit /b 1
if /I not "%TARGET_DIR%"=="%ADDONS_DIR%\%ADDON_FOLDER%" exit /b 1
exit /b 0

:NoAddOns
echo Could not find a WoW Classic AddOns folder.
echo.
echo Run again with the AddOns path:
echo   %~nx0 "C:\Path\World of Warcraft\_classic_era_\Interface\AddOns"
echo.
echo You can also drag the AddOns folder onto this file.
exit /b 1

:Help
echo Installs or updates WoW Experimental Playground in a WoW Classic AddOns folder.
echo.
echo Usage:
echo   %~nx0
echo   %~nx0 "C:\Path\World of Warcraft\_classic_era_\Interface\AddOns"
echo.
echo Existing local changes inside the addon folder are overwritten.
exit /b 0

:Fail
echo.
echo Install failed.
exit /b 1
