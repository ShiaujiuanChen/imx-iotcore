Usage
=====

Create an installation SD
--------------------------

Open Windows PowerShell as an administrator.
Run 'mk_sd_installer /apply disk_number' to apply the image to the SD card.


SD card disk number
--------------------------

Insert the SD card into your computer, and determine the physical disk number by running

diskpart
> list disk
> exit

The output looks like,

DISKPART> list disk

  Disk ###  Status         Size     Free     Dyn  Gpt
  --------  -------------  -------  -------  ---  ---
  Disk 0    Online          931 GB      0 B        *
  Disk 1    Online          931 GB      0 B
  Disk 2    Online          953 GB      0 B        *
* Disk 3    Online           14 GB      0 B

In this example, the physical disk number is 3.


Update installation SD
--------------------------

Copy Flash.ffu to [SD card partition 1]
Or run 'mk_sd_installer.cmd /apply disk_number [/ffu ffu_path]' to apply the latest image to the SD card.

