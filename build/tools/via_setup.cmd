@echo off

set WPE_FLASH_MARK=wpe_flash_reboot

for /f "tokens=2 delims=:" %%i in ('ipconfig /all ^| find /i "physical address"') do for /f "tokens=1-6 delims=- " %%a in ("%%i") do set MAC=%%a%%b%%c%%d%%e%%f
echo > %MAC%
for /f %%i in ('dir /b/l %MAC%') do set MAC=%%i

echo.
echo Deploying Flash.ffu to eMMC

if exist c:\%WPE_FLASH_MARK% ( del c:\%WPE_FLASH_MARK% )

dism /Apply-Image /ImageFile:c:\Flash.ffu /ApplyDrive:\\.\PhysicalDrive1 /skipplatformcheck

echo.

if %errorlevel% EQU 0 (
  echo %MAC:~0,2%:%MAC:~2,2%:%MAC:~4,2%:%MAC:~6,2%:%MAC:~8,2%:%MAC:~10,2% > c:\%WPE_FLASH_MARK%
  echo [92mSuccessfully flashed a new image to eMMC.[0m
  wpeutil reboot
) else (
  echo [31mUnable to flash a new image to eMMC![0m
)
