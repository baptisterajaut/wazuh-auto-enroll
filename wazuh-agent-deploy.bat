@echo off
setlocal enabledelayedexpansion
:: Wazuh Agent - Automatic installation
:: Run as administrator (right-click > Run as administrator)
:: Place a config.key file in the same folder as this script

net session >nul 2>&1 || (echo Run this script as administrator. & pause & exit /b 1)

:: --- Locate config.key next to this script ---
set "SCRIPT_DIR=%~dp0"
set "KEY_FILE=%SCRIPT_DIR%config.key"

if not exist "%KEY_FILE%" (
    echo config.key not found in %SCRIPT_DIR%
    pause
    exit /b 1
)

:: --- Parse config.key ---
set WAZUH_MANAGER=
set WAZUH_REGISTRATION_PASSWORD=
set WAZUH_GROUP=

for /f "usebackq tokens=1,* delims==" %%A in ("%KEY_FILE%") do (
    if "%%A"=="manager" set "WAZUH_MANAGER=%%B"
    if "%%A"=="password" set "WAZUH_REGISTRATION_PASSWORD=%%B"
    if "%%A"=="group" set "WAZUH_GROUP=%%B"
)

if "%WAZUH_MANAGER%"=="" (echo Missing 'manager' in config.key & pause & exit /b 1)
if "%WAZUH_REGISTRATION_PASSWORD%"=="" (echo Missing 'password' in config.key & pause & exit /b 1)
if "%WAZUH_GROUP%"=="" (echo Missing 'group' in config.key & pause & exit /b 1)

:: --- Agent name (hostname by default, override with config.key 'name' field or interactive prompt) ---
set "AGENT_NAME=%COMPUTERNAME%"
set "NAME_FROM_KEY="
for /f "usebackq tokens=1,* delims==" %%A in ("%KEY_FILE%") do (
    if "%%A"=="name" (
        set "AGENT_NAME=%%B"
        set "NAME_FROM_KEY=1"
    )
)

if not defined NAME_FROM_KEY (
    echo.
    set /p "AGENT_NAME=Agent name [%COMPUTERNAME%]: "
    if "!AGENT_NAME!"=="" set "AGENT_NAME=%COMPUTERNAME%"
)

echo Manager: %WAZUH_MANAGER% ^| Group: %WAZUH_GROUP% ^| Agent: %AGENT_NAME%

:: --- Download and install ---
set "WAZUH_MSI=%TEMP%\wazuh-agent.msi"

echo Downloading Wazuh agent...
powershell -Command "Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.3-1.msi' -OutFile '%WAZUH_MSI%'"

echo Installing...
msiexec /i "%WAZUH_MSI%" /q WAZUH_MANAGER="%WAZUH_MANAGER%" WAZUH_REGISTRATION_PASSWORD="%WAZUH_REGISTRATION_PASSWORD%" WAZUH_AGENT_GROUP="%WAZUH_GROUP%" WAZUH_AGENT_NAME="%AGENT_NAME%"

echo Starting service...
NET START WazuhSvc

echo.
echo Done! Agent '%AGENT_NAME%' enrolled to %WAZUH_MANAGER% (group: %WAZUH_GROUP%)
pause
