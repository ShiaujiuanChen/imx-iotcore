::
:: Prepares a WinPE image for boot on i.MX6
::
@echo off
setlocal enableextensions disabledelayedexpansion

set DEST=winpe_imx
set SCRIPT_DIR=%~dp0
set SCRIPT_CMD=%~nx0

:: make WIM mount directory
rmdir /s /q mount > NUL 2>&1
mkdir mount
pushd mount
set MOUNT_DIR=%CD%
popd

:: Parse options
:GETOPTS
 if /I "%~1" == "/?" goto USAGE
 if /I "%~1" == "/Help" goto USAGE
 if /I "%~1" == "/ffu" set FFU_PATH=%2& shift
 if /I "%~1" == "/apply" set DISK_NUM=%2& shift
 if /I "%~1" == "/clean" set CLEAN=1
 shift
if not (%1)==() goto GETOPTS

if not "%CLEAN%" == "" goto CLEAN
if not "%DISK_NUM%" == "" goto APPLY
goto USAGE

:APPLY
    echo Applying image at %DEST% to physical disk %DISK_NUM%
    if not exist "%DEST%" (
        echo No WinPE media directory found at %DEST%. Run the first form of this script to generate WinPE image layout.
        exit /b 1
    )

    echo select disk %DISK_NUM% > diskpart.txt
    echo clean >> diskpart.txt
    echo convert mbr >> diskpart.txt
    echo create partition primary >> diskpart.txt
    echo format fs=fat32 label="WinPE" quick >> diskpart.txt
    echo active >> diskpart.txt
    echo assign >> diskpart.txt
    echo assign mount="%MOUNT_DIR%" >> diskpart.txt

    echo Formatting disk %DISK_NUM% and mounting to %MOUNT_DIR%...
    diskpart /s diskpart.txt || goto err

    echo Copying files from %DEST% to %MOUNT_DIR%
    xcopy /herky "%DEST%\*.*" "%MOUNT_DIR%\" || goto err

    echo Copying firmware_fit.merged to %MOUNT_DIR%
    copy "firmware_fit.merged" "%MOUNT_DIR%\" || goto err

    echo Copying uefi.fit to %MOUNT_DIR%
    copy "uefi.fit" "%MOUNT_DIR%\" || goto err

    if exist "%FFU_PATH%" (
        echo Copying %FFU_PATH% to %CD%
        copy "%FFU_PATH%" "Flash.ffu"
    )
    echo Copying Flash.ffu to %MOUNT_DIR%
    copy "Flash.ffu" "%MOUNT_DIR%\" || goto err

    mountvol "%MOUNT_DIR%" /d

    echo Writing firmware_fit.merged to \\.\PhysicalDrive%DISK_NUM%
    dd.exe "if=firmware_fit.merged" of=\\.\PhysicalDrive%DISK_NUM% bs=512 seek=2 || goto err

    echo Success
    echo.
    echo NOTE: please ignore "Error reading file: 87 The parameter is incorrect" if occured.
    echo.

    rmdir /s /q "%MOUNT_DIR%" 2> NUL
    del diskpart.txt

    exit /b 0

:CLEAN
    echo Cleaning up from previous run
    mountvol "%MOUNT_DIR%" /d > NUL 2>&1
    rmdir /s /q "%MOUNT_DIR%" 2> NUL
    del diskpart.txt 2> NUL
    exit /b 0

:USAGE
    echo.
    echo %SCRIPT_CMD% /apply disk_number [/ffu ffu_path]
    echo %SCRIPT_CMD% /clean
    echo.
    echo Creates a WinPE image for i.MX
    echo Options:
    echo.
    echo    /ffu ffu_path                Optionally specify an FFU to flash
    echo    /apply disk_number           Apply WinPE image to physical disk
    echo    /clean                       Clean up artifacts from a previous run.
    echo.
    echo Examples:
    echo.
    echo Apply the WinPE image to an SD card (Physical Disk 7, use diskpart to find the disk number)
    echo.
    echo    %SCRIPT_CMD% /apply 7
    echo.
    echo Clean up artifacts from a previous run of this script
    echo.
    echo    %SCRIPT_CMD% /clean
    echo.
    exit /b 0

:err
    echo Script failed! Cleaning up
    mountvol "%MOUNT_DIR%" /d > NUL 2>&1
    exit /b 1

