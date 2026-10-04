#!/bin/bash
echo "This is not a script that should be ran automatically!"
echo "Please open the file and do the updates one by one!"
exit 0

##############################################################################
# This script is for manually updating the firmware for you DGX10/GX10/...
# Please download the firmware archive from your manufacturers support site
# And follow the steps from below, please do note that you have to patch
# the files in the order found below at FILES TO UPDATE
#
# Please read the file one time to know what to do, it is also recommended
# to put the extracted firmware files on a persistant storage pool like your
# main pool, like /mnt/nvme/update and copy the files from there.
##############################################################################

# Basic steps to execute before copying the files and after a reboot
yes | apt update
yes | apt install efivar
mkdir -p /tmp/efi
mount /dev/nvme0n1p1 /tmp/efi
mkdir -p /tmp/efi/EFI/UpdateCapsule
ls /tmp/efi/EFI/UpdateCapsule
# The last ls is just to check if the directory is empty and the update from
# the previous file went through

# Copy the listed files at FILES TO UPDATE (start with 1, continue with 2 after
# the reboot and so on) to the directory:
# /tmp/efi/EFI/UpdateCapsule
# Continue with these commands, this will trigger an automatic reboot:
sync
umount /tmp/efi
printf '\x04\x00\x00\x00\x00\x00\x00\x00' > /tmp/set_cap_flag.bin
efivar --print --name "8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications"
efivar -w --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications -f /tmp/set_cap_flag.bin
efivar --print --name "8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications"
reboot


#############################
# FILES TO UPDATE
#############################
1	bsp_ota2604_socfw307_bios_0105_ec_3.3.2.4_signed.cap       open
2	ec_3.3.2.4_signed.cap                                      open
3	usbpd_5.22.cap                                             open
4	usbpd_5.22.cap (again!)                                    open
5	tpm_7.2.4.1.cap                                            open

##############################################################################
# After updating all firmware files you can check if all update correctly:
##############################################################################
yes | apt update
yes | apt install fwupd
fwupdtool get-devices --show-all
