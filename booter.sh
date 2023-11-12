#!/bin/bash

# Synopsys: This file is intended to run on a LiveCD Arch Linux system.
# and is intended to install a base system to a specified disk, along with some
# necessary packages and configuration files.

# Propper usage to run this script should be curl https://raw.githubusercontent.com/portalmaster137/ArchyBootstrapper/main/booter.sh | bash

## STAGE 1 : CONFIGURATION ##

#First, determine if this is a UEFI or BIOS system.
BIOS=False
UEFI=False
if [ -d "/sys/firmware/efi/efivars" ]; then
    
    # cat'ing /sys/firmware/efi/fw_platform_size will return the size of the UEFI firmware in bits, either 32 or 64.
    # 32 bit UEFI systems are not supported by Arch Linux, so we will exit if this is the case.
    if [ $(cat /sys/firmware/efi/fw_platform_size) -eq 32 ]; then
        echo "32 bit UEFI systems are not supported by this installer. Exiting."
        exit 1
    fi
    UEFI=True
    echo "UEFI system detected."
else
    BIOS=True
    echo "BIOS system detected."
fi