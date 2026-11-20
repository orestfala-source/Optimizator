@echo off
chcp 65001 >nul
setlocal
rem ================================================================
rem  Optimizator: збірка програми + інсталера Optimizator-Setup.exe
rem  Потрібно: .NET 10 SDK. Inno Setup поставиться сам через winget.
rem ================================================================
cd /d "%~dp0"
set /p VERSION=<..\VERSION

where dotnet >nul 2>nul
if errorlevel 1 goto :nodotnet

echo.
echo [1/2] Збірка Optimizator %VERSION%...
if exist publish rmdir /s /q publish
dotnet publish Optimizator.csproj -c Release -r win-x64 --self-contained true -p:PublishReadyToRun=true -p:Version=%VERSION% -o publish
if errorlevel 1 goto :fail

echo.
echo [2/2] Збірка інсталера...
call :findiscc
if defined ISCC goto :compile
echo Inno Setup не знайдено — встановлюю через winget...
winget install -e --id JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements
call :findiscc
if not defined ISCC goto :noiscc

:compile
"%ISCC%" /Qp /DAppVersion=%VERSION% installer\Optimizator.iss
if errorlevel 1 goto :fail

echo.
echo Готово: %~dp0dist\Optimizator-Setup-%VERSION%.exe
start "" explorer "%~dp0dist"
pause
exit /b 0

:findiscc
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
exit /b 0

:nodotnet
echo Не знайдено .NET SDK. Встанови .NET 10 SDK: https://dotnet.microsoft.com/download/dotnet/10.0
pause
exit /b 1

:noiscc
echo Не вдалося встановити Inno Setup. Завантаж його вручну: https://jrsoftware.org/isdl.php
pause
exit /b 1

:fail
echo.
echo Помилка збірки — дивись повідомлення вище.
pause
exit /b 1
