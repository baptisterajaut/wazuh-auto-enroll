@echo off
:: Wazuh Agent - Installation automatique
:: Lancer en tant qu'administrateur (clic droit > Executer en tant qu'administrateur)
:: Place un fichier config.key dans le meme dossier que ce script

net session >nul 2>&1 || (echo Lancez ce script en tant qu'administrateur. & pause & exit /b 1)

:: --- Locate config.key next to this script ---
set "SCRIPT_DIR=%~dp0"
set "KEY_FILE=%SCRIPT_DIR%config.key"

if not exist "%KEY_FILE%" (
    echo Fichier config.key introuvable dans %SCRIPT_DIR%
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

:: --- Agent name (hostname by default, override with config.key 'name' field) ---
set "AGENT_NAME=%COMPUTERNAME%"
for /f "usebackq tokens=1,* delims==" %%A in ("%KEY_FILE%") do (
    if "%%A"=="name" set "AGENT_NAME=%%B"
)

echo Manager: %WAZUH_MANAGER% ^| Group: %WAZUH_GROUP% ^| Agent: %AGENT_NAME%

:: --- Download and install ---
set "WAZUH_MSI=%TEMP%\wazuh-agent.msi"

echo Telechargement de l'agent Wazuh...
powershell -Command "Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.3-1.msi' -OutFile '%WAZUH_MSI%'"

echo Installation en cours...
msiexec /i "%WAZUH_MSI%" /q WAZUH_MANAGER="%WAZUH_MANAGER%" WAZUH_REGISTRATION_PASSWORD="%WAZUH_REGISTRATION_PASSWORD%" WAZUH_AGENT_GROUP="%WAZUH_GROUP%" WAZUH_AGENT_NAME="%AGENT_NAME%"

echo Demarrage du service...
NET START WazuhSvc

echo.
echo Installation terminee ! Agent '%AGENT_NAME%' connecte a %WAZUH_MANAGER% (groupe: %WAZUH_GROUP%)
pause
