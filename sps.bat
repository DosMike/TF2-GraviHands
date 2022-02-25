@echo off
rem check if java is installed. this is a java application so proceeding
rem without makes no sense
where java >nul 2>&1
if %errorlevel% NEQ 0 (
 echo Could not find Java - SPSauce requires Java 8+
 echo You can get Java at https://adoptopenjdk.net
 echo.
 echo Press any key to exit . . .
 pause >nul
 exit /B 1
)
rem check if git is installed, dependency clone might fail if missing
rem since this is not critical to any other dependency type, i'll just warn
where git >nul 2>&1
if %errorlevel% NEQ 0 (
 echo Could not find git - Some dependencies might fail!
 echo You can get git from https://git-scm.com/
 echo.
)
rem while the cache will be local to the spsauce file the
rem application (and this script) might be relocated to a global
rem installation (so sps.bat would be in path)
rem thus we will search the .jar relative to the .bat
pushd %~dp0
for /f "delims=" %%F in ('dir spsauce\SPSauce-*.jar /b /o-n') do set spsfile=%%F
popd
if "%spsfile%"=="" (
 echo Could not find any SPSauce jar binary
 exit /B 1
)
set spsfile=%~dp0spsauce\%spsfile%
rem call the java application with the args
call java -jar "%spsfile%" %*
if %errorlevel% NEQ 0 pause