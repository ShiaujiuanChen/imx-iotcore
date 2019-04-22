::
:: Prepares a WinPE image for boot on i.MX6 or i.MX7
::
@echo off
setlocal enableextensions disabledelayedexpansion

set WINPE_DIR=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\arm
set DEST=winpe_imx
set SCRIPT_DIR=%~dp0
set SCRIPT_CMD=%~nx0
set BUILD_DIR=%SCRIPT_DIR%..\solution\iMXPlatform\Build\ARM\Release\
set FIRMWARE_PATH=%SCRIPT_DIR%..\board\VAB820_iMX6Q_1GB\Package\BootLoader\firmware_fit.merged
set UEFI_PATH=%SCRIPT_DIR%..\board\VAB820_iMX6Q_1GB\Package\BootFirmware\uefi.fit
set FFU_PATH=%SCRIPT_DIR%..\solution\iMXPlatform\Build\FFU\VAB820_iMX6Q_1GB\VAB820_iMX6Q_1GB_TestOEMInput.xml.Release.ffu

:: make WIM mount directory
rmdir /s /q mount > NUL 2>&1
mkdir mount
pushd mount
set MOUNT_DIR=%CD%
popd

:: make directory to hold packages
rmdir /s /q packages > NUL 2>&1
mkdir packages
pushd packages
set PACKAGES_DIR=%CD%
popd

:: Parse options
:GETOPTS
 if /I "%~1" == "/?" goto USAGE
 if /I "%~1" == "/Help" goto USAGE
 if /I "%~1" == "/builddir" set BUILD_DIR=%2& shift
 if /I "%~1" == "/firmware" set FIRMWARE_PATH=%2& shift
 if /I "%~1" == "/uefi" set UEFI_PATH=%2& shift
 if /I "%~1" == "/ffu" set FFU_PATH=%2& shift
 if /I "%~1" == "/apply" set DISK_NUM=%2& shift
 if /I "%~1" == "/clean" set CLEAN=1
 shift
if not (%1)==() goto GETOPTS

if not "%CLEAN%" == "" goto CLEAN
if not "%DISK_NUM%" == "" goto APPLY

if not exist "%BUILD_DIR%" (
    echo Missing required option '/builddir'. Type /? for usage.
    exit /b 1
)

if not exist "%FIRMWARE_PATH%" (
    echo Missing required option '/firmware'. Type /? for usage.
    exit /b 1
)

if not exist "%UEFI_PATH%" (
    echo Missing required option '/uefi'. Type /? for usage.
    exit /b 1
)

if not exist "%FFU_PATH%" (
    echo Missing required option '/ffu'. Type /? for usage.
    exit /b 1
)

:: make temporary WinPE directory
rmdir /s /q "%DEST%" > NUL 2>&1
mkdir "%DEST%"
mkdir "%DEST%\sources"

:: copy firmware files
echo Copying firmware from %FIRMWARE_PATH%
copy "%FIRMWARE_PATH%" "firmware_fit.merged" /y || goto err

echo Copying UEFI from %UEFI_PATH%
copy "%UEFI_PATH%" "uefi.fit" /y || goto err

:: copy winpe files
echo Creating WinPE image layout at %DEST%
echo Copying WinPE files from %WINPE_DIR%
if not exist "%WINPE_DIR%\Media" (
    echo You must install the Windows PE Add-on for the ADK
    echo https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/download-winpe--windows-pe
    goto err
)
xcopy /herky "%WINPE_DIR%\Media" "%DEST%\" || goto err
copy "%WINPE_DIR%\en-us\winpe.wim" "%DEST%\sources\boot.wim" || goto err
move "%DEST%\bootmgr.efi" "%DEST%\EFI\Microsoft\boot\" || goto err

:: BCD
echo Enabling kernel debugging
set TARGET_BCD_STORE=%DEST%\EFI\Microsoft\boot\bcd
bcdedit /store "%TARGET_BCD_STORE%" /dbgsettings SERIAL DEBUGPORT:1 BAUDRATE:115200 || goto err
bcdedit /store "%TARGET_BCD_STORE%" /debug {default} on || goto err

echo Enable boot test/flight signing
bcdedit /store "%TARGET_BCD_STORE%" /set {bootmgr} flightsigning on || goto err
bcdedit /store "%TARGET_BCD_STORE%" /set {bootmgr} testsigning on || goto err

echo Enable kernel test/flight signing...
bcdedit /store "%TARGET_BCD_STORE%" /set {default} testsigning on || goto err
bcdedit /store "%TARGET_BCD_STORE%" /set {default} flightsigning on || goto err

mkdir "%MOUNT_DIR%" > NUL 2>&1
echo Mounting WIM at %MOUNT_DIR%
dism /mount-wim /wimfile:"%DEST%\sources\boot.wim" /mountdir:"%MOUNT_DIR%" /index:1 || goto err

set STARTNET_CMD=%MOUNT_DIR%\Windows\System32\startnet.cmd

echo Setting up FFU deployment to MMC
copy "%FFU_PATH%" "Flash.ffu" /y || goto err

echo Appending FFU flashing commands to %STARTNET_CMD%
echo via_setup.cmd >> "%STARTNET_CMD%"

echo Copying %SCRIPT_DIR%via_setup.cmd to %MOUNT_DIR%\Windows\System32\
copy "%SCRIPT_DIR%via_setup.cmd" "%MOUNT_DIR%\Windows\System32\"

echo Copying %SCRIPT_DIR%boot.scr %DEST%\
copy "%SCRIPT_DIR%boot.scr" "%DEST%\"

echo Copying driver packages to %PACKAGES_DIR%
call :GETPACKAGE NXP.iMX.HalExtiMX6Timers.cab || goto err
call :GETPACKAGE NXP.iMX7.HalExtiMX7Timers.cab || goto err
call :GETPACKAGE NXP.iMX.HalExtiMXDma.cab || goto err
call :GETPACKAGE NXP.iMX.imxecspi.cab || goto err
call :GETPACKAGE NXP.iMX.imxgpio.cab || goto err
call :GETPACKAGE NXP.iMX.imxi2c.cab || goto err
call :GETPACKAGE NXP.iMX.imxnetmini.cab || goto err
call :GETPACKAGE NXP.iMX.imxuart.cab || goto err
call :GETPACKAGE NXP.iMX.imxusdhc.cab || goto err
call :GETPACKAGE NXP.iMX.mx6pep.cab || goto err

echo Injecting drivers from %PACKAGES_DIR% into WIM
dism /image:"%MOUNT_DIR%" /Add-Package /packagepath:"%PACKAGES_DIR%" || goto err

echo Unmounting WIM
dism /unmount-wim /mountdir:"%MOUNT_DIR%" /commit || goto err

rmdir /s /q "%MOUNT_DIR%" 2> NUL
rmdir /s /q "%PACKAGES_DIR%" 2> NUL

echo Success
exit /b 0

:GETPACKAGE
    setlocal enableextensions disabledelayedexpansion
    dir "%BUILD_DIR%\*%1" /s /b > %TMP%/temp.txt
    set /p PACKAGE_PATH=<%TMP%/temp.txt
    if "%PACKAGE_PATH%" == "" (
        echo Error: could not find %1 in %BUILD_DIR%
        exit /b 1
    )
    echo Copying %PACKAGE_PATH% to %PACKAGES_DIR%
    copy "%PACKAGE_PATH%" "%PACKAGES_DIR%"
    exit /b %ERRORLEVEL%

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
    rmdir /s /q "%PACKAGES_DIR%" 2> NUL
    del diskpart.txt

    exit /b 0

:CLEAN
    echo Cleaning up from previous run
    dism /unmount-wim /mountdir:"%MOUNT_DIR%" /discard > NUL 2>&1
    rmdir /s /q "%MOUNT_DIR%" 2> NUL
    rmdir /s /q "%PACKAGES_DIR%" 2> NUL
    rmdir /s /q "%DEST%" 2> NUL
    del firmware_fit.merged 2> NUL
    del uefi.fit 2> NUL
    del Flash.ffu 2> NUL
    del diskpart.txt 2> NUL
    exit /b 0

:USAGE
    echo %SCRIPT_CMD% /builddir build_dir /firmware firmware_fit_path /uefi uefi_fit_path /ffu ffu_path
    echo %SCRIPT_CMD% /apply disk_number
    echo %SCRIPT_CMD% /clean
    echo.
    echo Creates a WinPE image for i.MX
    echo Options:
    echo.
    echo    /builddir build_dir          Path to build output directory.
    echo    /firmware firmware_fit_path  Path to firmware_fit.merged
    echo    /uefi uefi_fit_path          Path to uefi.fit
    echo    /ffu ffu_path                Optionally specify an FFU to flash
    echo    /apply disk_number           Apply WinPE image to physical disk
    echo    /clean                       Clean up artifacts from a previous run.
    echo.
    echo Examples:
    echo.
    echo Create a WinPE image that deploys an FFU to MMC.
    echo.
    echo    %SCRIPT_CMD% /builddir d:\build\Binaries\release\ARM /firmware d:\build\FFU\HummingBoardEdge_iMX6Q_2GB\Package\BootLoader\firmware_fit.merged /uefi d:\build\FFU\HummingBoardEdge_iMX6Q_2GB\Package\BootFirmware\uefi.fit /ffu d:\build\FFU\HummingBoardEdge_iMX6Q_2GB\HummingBoardEdge_iMX6Q_2GB_TestOEMInput.xml.Release.ffu
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
    dism /unmount-wim /mountdir:"%MOUNT_DIR%" /discard
    mountvol "%MOUNT_DIR%" /d > NUL 2>&1
    exit /b 1

