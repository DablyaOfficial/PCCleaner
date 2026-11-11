@echo off
rem Builds ..\PCCleaner.exe from PCCleaner.ps1 + Launcher.cs using the C# compiler shipped with Windows.
cd /d "%~dp0"
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
set SMA=%WINDIR%\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll
set OUT=%~1
if "%OUT%"=="" set OUT=..\PCCleaner.exe
set MAN=/win32manifest:app.manifest
if "%~2"=="nomanifest" set MAN=
"%CSC%" /nologo /target:winexe /platform:x64 /optimize+ /out:"%OUT%" %MAN% /resource:PCCleaner.ps1,PCCleaner.ps1 /reference:"%SMA%" /reference:System.Windows.Forms.dll Launcher.cs
if errorlevel 1 (echo BUILD FAILED & exit /b 1)
echo Built %OUT%
