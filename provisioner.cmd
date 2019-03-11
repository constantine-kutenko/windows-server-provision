echo off
cls

:: Define variables

:: Define a new Remote Desktop Servies TCP port
set WIN_RDP_PORT=6666

:: Define details for a service to be changed
set WIN_SERVICE_NAME=
REM set WIN_SERVICE_NAME=<service_name>
REM set WIN_SERVICE_USERNAME=<username>
REM set WIN_SERVICE_PASSWORD=<password>

:: Define a list of users and passwords to be added. If the list is empty, no actions will be made
:: Format: <username>/<password>
:: WARNING: A password MUST NOT contain specific symbols like !@#$%^&*(){}[]></. Only alphanumeric symbols are allowed
set WIN_CREDENTIALS=
REM set WIN_CREDENTIALS=user01/Password001 user02/Password002 user03/Password003 user04/Password004 user05/Password005


:: Define a group for the new users
:: Format: "<groupname with whitespaces>" <group_name> <...>
:: WARNING: It's possible to define only one group so far
set WIN_USER_GROUP=
REM set WIN_USER_GROUP="Remote Desktop Users" Administrators

:: Define a list of accounts to be renamed. If the list is empty, no actions will be made
:: Format: <current_username>/<new_username>
set WIN_USERS_RENAME=
REM set WIN_USERS_RENAME=user01/user001 user02/user002 user03/user003 user04/user004 user05/user005

set ERRORLEVEL=0

:: Verify the user launched the script
for /F "tokens=*" %%a in ('whoami') do set CURRENT_USER=%%a
call set KEY=%%CURRENT_USER:\=%%
if not "x%KEY%"=="x%CURRENT_USER%" (
    :: server os
    for /f "tokens=1,2 delims=\" %%a in ("%CURRENT_USER%") do ( set CURRENT_USER=%%b )
    goto verify_priv
) else (
    :: desktop os
    goto verify_priv
)

:verify_priv
if not %CURRENT_USER%==administrator (
    if not %CURRENT_USER%==Administrator (
        echo Lauch the script with administrative privileges. Current user: %CURRENT_USER%
        exit /b 1
    )
)

:: Determine and parse system version
FOR /F "tokens=* USEBACKQ" %%F IN (`ver`) DO (
SET VERSION=%%F
)
for /f "tokens=1,2 delims=[" %%a in ("%VERSION%") do ( set SUBSTRING=%%b )
for /f "tokens=1,2 delims=]" %%a in ("%SUBSTRING%") do ( set SUBSTRING=%%a )
for /f "tokens=2 delims= " %%a in ("%SUBSTRING%") do ( set SUBSTRING=%%a )

if %SUBSTRING%==6.1.7601 ( 
    goto win7sp1
) ELSE if %SUBSTRING%==6.2.9200 ( 
    goto win2012
) ELSE if %SUBSTRING%==6.3.9600 ( 
    goto win2012r2 
) ELSE (
    echo Unsupported version of Windows
    goto end
)

:win7sp1
    echo Perform actions for Windows 7 Service Pack 1
    goto apply

:win2012
    echo Perform actions for Windows Server 2012
    goto apply

:win2012r2
    echo Perform actions for Windows Server 2012 R2
    goto apply

:apply
    echo.
    echo Setting local accounts properties...
    echo.

    ::
    :: Renaming local accounts 
    ::

    setlocal enableextensions
    if defined WIN_USERS_RENAME (
        echo Renaming local accounts
        echo.

        setlocal enabledelayedexpansion
        for %%s in (%WIN_USERS_RENAME%) do (
            set VAR=%%s
            for /f "tokens=1,2 delims=/" %%a in ("!VAR!") do ( 
                set CURRENT_USERNAME=%%a
            )
            for /f "tokens=1,2 delims=/" %%a in ("!VAR!") do ( 
                set NEW_USERNAME=%%b
            )
            REM echo "!CURRENT_USERNAME!" "!NEW_USERNAME!"

            :: Rename a local account
            echo Rename "!CURRENT_USERNAME!" to "!NEW_USERNAME!"
            set CMD=wmic useraccount where name="!CURRENT_USERNAME!" rename "!NEW_USERNAME!"
            REM echo !CMD!
            call !CMD!
        )
    )
    endlocal

    ::
    :: Adding local accounts
    ::

    setlocal enableextensions
    if defined WIN_CREDENTIALS (
        echo Adding local accounts
        echo.

        set CREDENTIAL=
        setlocal enabledelayedexpansion
        for %%s in (%WIN_CREDENTIALS%) do (
            set CREDENTIAL=%%s
            for /f "tokens=1,2 delims=/" %%a in ("!CREDENTIAL!") do ( 
                set ACCOUNT_NAME=%%a
            )
            for /f "tokens=1,2 delims=/" %%a in ("!CREDENTIAL!") do ( 
                set ACCOUNT_PASSWORD=%%b
            )

            REM echo !ACCOUNT_NAME! !ACCOUNT_PASSWORD!
            
            set RESULT=
            call net user | findstr /i !ACCOUNT_NAME! >nul && (
                echo Local account "!ACCOUNT_NAME!" already exists
            ) || (
                REM echo Local account "!ACCOUNT_NAME!" doesn't exist
                :: Create a user account
                echo Creating account !ACCOUNT_NAME!
                set CMD=net user !ACCOUNT_NAME! !ACCOUNT_PASSWORD! /add
                REM echo !CMD!
                call !CMD!

                :: Add a new user to certain groups if they're defined
                if defined !%WIN_USER_GROUP%! (
                    for %%a in (%WIN_USER_GROUP%) do (
                        set GROUP_NAME=%%~a
                        echo Adding account !ACCOUNT_NAME! to group !GROUP_NAME!
                        set CMD=net localgroup "!GROUP_NAME!" !ACCOUNT_NAME! /add
                        REM echo !CMD!
                        call !CMD!
                    )
                )
                echo.
            )
        )
    )
    endlocal

    setlocal enableextensions enabledelayedexpansion
    if defined WIN_SERVICE_NAME (
        echo.
        echo Setting properties for service %WIN_SERVICE_NAME%
        echo.

        echo Stopping service %WIN_SERVICE_NAME%
        call set CMD=sc Stop %WIN_SERVICE_NAME%
        REM echo !CMD!
        call !CMD! >nul
        ping -n 4 127.0.0.1 >nul

        echo Setting properties for %WIN_SERVICE_NAME%
        call set CMD=sc config %WIN_SERVICE_NAME% obj= %COMPUTERNAME%\%WIN_SERVICE_USERNAME% password= %WIN_SERVICE_PASSWORD%
        REM echo !CMD!
        call !CMD!

        echo Starting service %WIN_SERVICE_NAME%
        call set CMD=sc Start %WIN_SERVICE_NAME%
        REM echo !CMD!
        call !CMD!
    ) else (
        echo Service name is not defined. Nothing to do.
    )
    endlocal

    setlocal enableextensions enabledelayedexpansion
    if defined WIN_RDP_PORT (
        echo Configuring RDP connections...
        
        :: Enable remote desktop service
        :: reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f

        echo Replace the TCP port used by RDP service
        call set CMD=reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v PortNumber /t REG_DWORD /d !WIN_RDP_PORT! /f
        call !CMD! > Nul
        REM echo !CMD!
        if %ERRORLEVEL%==0 (
            echo Success
        ) else (
            echo Error: could not change RDP port number
        )

        echo.

        :: Verify if a rule exists
        call set WIN_FW_RULE_NAME=Allow incoming RDP connections (TCP/!WIN_RDP_PORT!^)
        netsh advfirewall firewall show rule name="!WIN_FW_RULE_NAME!" | findstr "no rules" >nul && (
            :: A rule doesn't exist
            echo Create a firewall rule for incoming RDP connections on port TCP/%WIN_RDP_PORT%
            call set CMD=netsh advfirewall firewall add rule name="!WIN_FW_RULE_NAME!" dir=in protocol=TCP localport=%WIN_RDP_PORT% action=allow enable=yes
            REM echo !CMD!
            call !CMD! > Nul
            if %ERRORLEVEL%==0 (
                echo Success
            ) else (
                echo Error: could not add a firewall rule for TCP/%WIN_RDP_PORT%
            )
        ) || (
                :: A rule exists
                echo A rule for port %WIN_RDP_PORT% already exists
            )
    )
    endlocal

if %ERRORLEVEL%==0 (
    echo.
    echo It's all done. Restart the computer
    pause
)
