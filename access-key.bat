@echo off
setlocal enabledelayedexpansion

:: Usage:
:: 1) interactive: double-click or run without args -> prompts for key/secret/region/profile
:: 2) args: aws-cred-setup.bat <ACCESS_KEY> <SECRET_KEY> <REGION> <PROFILE>
:: Example: aws-cred-setup.bat AKIA... wJalrXUtnFEMI/K7MDENG us-east-1 myprofile

:: Check args count
if "%~1"=="" goto interactive_mode
if "%~1"=="-i" goto interactive_mode

:: Args mode
set "AWS_ACCESS_KEY_ID=%~1"
set "AWS_SECRET_ACCESS_KEY=%~2"
set "AWS_DEFAULT_REGION=%~3"
set "AWS_PROFILE=%~4"
if "%AWS_PROFILE%"=="" set "AWS_PROFILE=default"
goto save_credentials

:interactive_mode
set /p "AWS_ACCESS_KEY_ID=Enter AWS Access Key ID: "
set /p "AWS_SECRET_ACCESS_KEY=Enter AWS Secret Access Key: "
set /p "AWS_DEFAULT_REGION=Enter AWS Region (e.g. us-east-1) [leave blank for us-east-1]: "
if "%AWS_DEFAULT_REGION%"=="" set "AWS_DEFAULT_REGION=us-east-1"
set /p "AWS_PROFILE=Enter profile name [default]: "
if "%AWS_PROFILE%"=="" set "AWS_PROFILE=default"

:save_credentials
echo.
echo Saving credentials to profile "%AWS_PROFILE%"...

:: If aws cli is present, prefer to use it
where aws >nul 2>&1
if %errorlevel%==0 (
    echo aws CLI found. Storing using "aws configure set"...
    :: Use aws configure set to save credentials and region under profile
    aws configure set aws_access_key_id "%AWS_ACCESS_KEY_ID%" --profile %AWS_PROFILE%
    aws configure set aws_secret_access_key "%AWS_SECRET_ACCESS_KEY%" --profile %AWS_PROFILE%
    aws configure set region "%AWS_DEFAULT_REGION%" --profile %AWS_PROFILE%
    if %errorlevel%==0 (
        echo Saved to AWS CLI profile "%AWS_PROFILE%".
        echo To use it in PowerShell/CMD: setx AWS_PROFILE "%AWS_PROFILE%"
    ) else (
        echo Failed to save using aws CLI. Will try file write fallback.
        goto file_write
    )
) else (
    echo aws CLI not found. Writing files directly to %%USERPROFILE%%\.aws\...
    goto file_write
)
goto done

:file_write
set "AWS_DIR=%USERPROFILE%\.aws"
if not exist "%AWS_DIR%" mkdir "%AWS_DIR%"

:: Write credentials (will overwrite existing profile block with same name by creating a temp file)
set "CREDFILE=%AWS_DIR%\credentials"
set "TMP=%TEMP%\aws_creds_tmp.txt"

:: Build credentials content: preserve other profiles if present
if exist "%CREDFILE%" (
    type "%CREDFILE%" > "%TMP%"
) else (
    break> "%TMP%"
)

:: Remove any existing profile block for this profile from TMP and append a new one.
:: Simple approach: create a new file with all lines except the profile block.
setlocal disableDelayedExpansion
(for /f "usebackq delims=" %%A in ("%TMP%") do (
    call :skip_profile "%%A"
)) > "%TMP%.out"
endlocal

:: Append (or add) our profile block
(
    echo [%AWS_PROFILE%]
    echo aws_access_key_id = %AWS_ACCESS_KEY_ID%
    echo aws_secret_access_key = %AWS_SECRET_ACCESS_KEY%
) >> "%TMP%.out"

move /y "%TMP%.out" "%CREDFILE%" >nul

:: Write config (region) to config file
set "CONFIGFILE=%AWS_DIR%\config"
if exist "%CONFIGFILE%" (
    type "%CONFIGFILE%" > "%TMP%"
) else (
    break> "%TMP%"
)

setlocal disableDelayedExpansion
(for /f "usebackq delims=" %%A in ("%TMP%") do (
    call :skip_profile_config "%%A"
)) > "%TMP%.out"
endlocal

:: Note: in config file profile sections are prefixed with "profile NAME" except default
if /i "%AWS_PROFILE%"=="default" (
    echo [default] >> "%TMP%.out"
) else (
    echo [profile %AWS_PROFILE%] >> "%TMP%.out"
)
echo region = %AWS_DEFAULT_REGION% >> "%TMP%.out"

move /y "%TMP%.out" "%CONFIGFILE%" >nul

echo Credentials and config saved to "%AWS_DIR%".
del "%TMP%" >nul 2>&1

goto done

:: Helpers for removing existing profile block from tmp (very simple implementation)
:skip_profile
rem arg1 = current line
setlocal enabledelayedexpansion
set "line=%~1"
endlocal & set "line=%line%"
rem This function is a no-op in this simple batch (robust parsing of INI sections in pure batch is complex).
rem For safety, we simply output all lines (so multiple duplicate profiles may occur). In production, use PowerShell.
echo %line%
goto :eof

:skip_profile_config
rem Same as above - we simply echo lines. See note above for production use.
setlocal enabledelayedexpansion
set "line=%~1"
endlocal & set "line=%line%"
echo %line%
goto :eof

:done
echo.
echo Done.
echo Tip: To use this profile for a single command in CMD:
echo    set AWS_PROFILE=%AWS_PROFILE% && aws s3 ls
echo Or to set it permanently for your user (new CMD sessions):
echo    setx AWS_PROFILE "%AWS_PROFILE%"
endlocal
exit /b 0
