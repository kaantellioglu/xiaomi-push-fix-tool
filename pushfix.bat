@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
chcp 65001 >nul 2>&1

echo ================================================
echo   XIAOMI PUSH FIX TOOL v1.0
echo   GitHub: https://github.com/kaantellioglu/xiaomi17-pro-max-push-fix-tool
echo ================================================

set LOGFILE=verify_log_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%.txt
set LOGFILE=%LOGFILE: =0%

echo.
echo Log file: %LOGFILE%
echo.

:: ── ADB CONNECTION CHECK ───────────────────────────
echo [1/8] Checking ADB connection...
.\adb start-server >nul 2>&1
.\adb get-state 1>nul 2>nul
if errorlevel 1 (
    echo [ERROR] Device not connected or USB debugging is disabled!
    echo         Connect your phone and allow USB debugging.
    pause
    exit /b 1
)

echo [OK] Device connected.

:: ── DEVICE INFO ───────────────────────────────────
for /f "delims=" %%D in ('.\adb shell getprop ro.product.model 2^>nul') do set MODEL=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.build.version.release 2^>nul') do set ANDROID=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.miui.ui.version.name 2^>nul') do set MIUI=%%D
for /f "delims=" %%D in ('.\adb shell getprop ro.product.region 2^>nul') do set REGION=%%D

echo     Model   : %MODEL%
echo     Android : %ANDROID%
echo     MIUI    : %MIUI%
echo     Region  : %REGION%

echo [DEVICE] %MODEL% Android=%ANDROID% MIUI=%MIUI% Region=%REGION% >> %LOGFILE%
echo.

:: ── DOZE STATUS ───────────────────────────────────
echo [2/8] Checking Doze (device idle) status...
.\adb shell dumpsys deviceidle > _doze_raw.txt 2>&1

findstr /i "mEnabled" _doze_raw.txt | findstr /i "false" >nul 2>&1
if not errorlevel 1 (
    echo [OK] Doze is DISABLED (ideal for push)
    echo [DOZE] DISABLED >> %LOGFILE%
) else (
    findstr /i "mEnabled" _doze_raw.txt | findstr /i "true" >nul 2>&1
    if not errorlevel 1 (
        echo [WARNING] Doze is ENABLED - run fix script after reboot!
        echo [DOZE] ENABLED >> %LOGFILE%
    ) else (
        echo [INFO] Unable to determine Doze state:
        findstr /i "enabled\|disabled\|idle" _doze_raw.txt
    )
)
echo.

:: ── DOZE DETAIL ───────────────────────────────────
echo [3/8] Doze detailed state:
for /f "delims=" %%L in ('.\adb shell dumpsys deviceidle ^| findstr /i "mState\|mLightState\|mode"') do (
    echo     %%L
    echo [DOZE_DETAIL] %%L >> %LOGFILE%
)
echo.

:: ── WHITELIST CHECK ───────────────────────────────
echo [4/8] Checking device idle whitelist...

set MISSING=0
set FOUND=0

.\adb shell dumpsys deviceidle whitelist > _wl_raw.txt 2>&1

for %%P in (
    com.google.android.gms
    com.google.android.gms.persistent
    com.google.android.gsf
    com.android.vending
    com.google.firebase.iid
    com.xiaomi.xmsf
    com.xiaomi.channel
    com.miui.powerkeeper
    com.whatsapp
    com.whatsapp.w4b
) do (
    findstr /i "%%P" _wl_raw.txt >nul 2>&1
    if not errorlevel 1 (
        echo   [OK]      %%P
        echo [WL_OK] %%P >> %LOGFILE%
        set /a FOUND+=1
    ) else (
        echo   [MISSING] %%P  ^<-- run fix script
        echo [WL_MISSING] %%P >> %LOGFILE%
        set /a MISSING+=1
    )
)

echo.
echo     Whitelist result: %FOUND% OK, %MISSING% missing
echo.

:: ── APPOPS CHECK ──────────────────────────────────
echo [5/8] Checking background execution permissions...

for %%P in (
    com.google.android.gms
    com.google.android.gsf
    com.xiaomi.xmsf
    com.whatsapp
) do (
    for /f "delims=" %%R in ('.\adb shell cmd appops get %%P RUN_ANY_IN_BACKGROUND 2^>nul') do (
        echo   [%%P]  %%R
        echo [APPOPS] %%P %%R >> %LOGFILE%
    )
)
echo.

:: ── NETWORK POLICY ────────────────────────────────
echo [6/8] Checking network policy...

for /f "delims=" %%L in ('.\adb shell cmd netpolicy list global 2^>nul') do (
    echo   %%L
    echo [NETPOLICY] %%L >> %LOGFILE%
)

.\adb shell settings get global restricted_networking_mode > _rnm.txt 2>&1
set /p RNM=<_rnm.txt

if "%RNM%"=="0" (
    echo   [OK] restricted_networking_mode = 0
) else (
    echo   [WARNING] restricted_networking_mode = %RNM%
)

echo.

:: ── GOOGLE SERVICES ───────────────────────────────
echo [7/8] Checking Google services...

for %%P in (
    com.google.android.gms
    com.google.android.gsf
    com.android.vending
) do (
    .\adb shell pm list packages %%P | findstr /i "%%P" >nul 2>&1
    if not errorlevel 1 (
        echo   [OK] %%P installed
    ) else (
        echo   [MISSING] %%P not installed!
    )
)
echo.

:: ── BACKGROUND LIMIT ──────────────────────────────
echo [8/8] Checking background process limit...

for /f "delims=" %%L in ('.\adb shell settings get global background_process_limit 2^>nul') do set BPL=%%L

if "%BPL%"=="-1" (
    echo   [OK] background_process_limit = -1 (unlimited)
) else (
    echo   [WARNING] background_process_limit = %BPL%
)

echo.

:: ── RESULT ────────────────────────────────────────
echo ================================================
echo   FINAL RESULT
echo ================================================

if %MISSING%==0 (
    echo [SUCCESS] All critical packages are whitelisted.
) else (
    echo [WARNING] %MISSING% packages missing from whitelist.
)

echo.
echo Full report saved: %LOGFILE%

del _doze_raw.txt _wl_raw.txt _rnm.txt >nul 2>&1

pause
endlocal
