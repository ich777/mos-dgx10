# MOS for NVIDIA DGX Spark, ASUS Ascent GX10 and equivalents

A customized version of [MOS](https://mos-official.net) built for the NVIDIA DGX Spark, ASUS Ascent GX10 and similar devices. This repository contains everything you need to install, update and maintain your system, including kernel builds, firmware update procedures and container configuration examples.

> **Important:** This is a starting point for getting MOS running on your device. After installation and initial setup, you should update your system, but make sure to disable kernel updates from the default MOS release. See the [Setup LXC Kernel Compilation](#setup-lxc-kernel-compilation) section for details.

> **Note:** This has only been tested on a single DGX Spark unit so far. RDMA functionality has not been verified yet, largely because the only thing standing between me and a second Spark for testing purposes is my wallet. These machines keep getting more expensive while my budget stays exactly where it was. So here we are, one Spark, no RDMA, full acceptance.

<p align="center">
  <img src="https://github.com/ich777/mos-dgx10/blob/master/images/dashbaord.png" width="800">
</p>

## Installation

### Step 1: Prepare bootable media

Download the latest release zip from the [Releases](https://github.com/ich777/mos-dgx10/releases) page of this repository and extract its contents to a FAT32 formatted USB drive. Detailed instructions can be found in the official [MOS installation docs](https://docs.mos-official.net/docs/Installation/Create-Bootable-Media).

### Step 2: Boot from USB

Insert the USB drive into your machine, power it on and enter the BIOS setup. Disable Secure Boot, save and exit, then re-enter the BIOS. Navigate to the boot override options and select your USB drive. MOS should now boot.

### Step 3: Choose your setup

Once the system has fully booted, open a browser on another machine on the same network and connect to the MOS Web UI to complete the initial setup wizard. You now have two options.

**Option A: Run permanently from USB**

If you prefer to leave MOS on the USB drive, simply change the boot order in your BIOS so the system always boots from the USB device. You are now done.

**Option B: Install to internal disk**

Go to **Settings** → **Boot** → **Install To Disk**. Select the target drive, choose your preferred filesystem, and make sure to enable **Extra Partition**.

Wait for the installation to complete, then shut down the system via **Settings** → **Shutdown**. Remove the USB drive and power the machine back on. MOS should now boot directly from the internal drive. If it does not, you may need to adjust the boot order in the BIOS once more, though this should normally not be necessary.

## Setting up the system

### Create a storage pool

After the installation is finished you need to create a pool. Depending on which installation option you chose, you can either use the whole disk or just the extra partition.

Go to **Pools**, click the three dots in the lower right corner and select **Create Pool**.

- **Name:** I would recommend `nvme`
- **Type:** Single
- **Devices:** Select the whole disk or the extra partition
- **Filesystem:** ext4 is recommended, as it will be useful later when creating a swapfile
- **Format:** Enabled
- **Automount:** Should already be enabled

Once the pool has been created you can store your models on the machine under `/mnt/nvme/models` (create the `models` directory there).

## Configuring the system

### System settings

Go to **Settings** → **System** and configure the following:

- Change your hostname if you want to
- Set your keymap (note that this is the keymap for the console)
- Set your timezone
- Choose your CPU governor

If you plan to use large models it is strongly recommended to enable a swapfile. Scroll down in the System settings to the **Swapfile** section and enable it. Set the path directly on your master pool, in our case `/mnt/nvme`, with a size of at least 30 (which means 30 GB). Set the swapfile priority to `-2`.

Do not forget to save your changes with the save icon in the lower right corner.

### Docker service

Go back to **Settings** and click on **Docker service**. Enable the service and make sure the paths are set correctly. Usually these should be:

- **Directory:** `/mnt/nvme/system/docker`
- **AppData:** `/mnt/nvme/appdata`

You can also change the network mode (ipvlan or macvlan) if needed. Click save in the lower right corner.

### LXC service

Again in **Settings**, click on **LXC service**. Enable the service and verify that the directory is set correctly, usually `/mnt/nvme/system/lxc`. You can also configure backups there if you want to (optional). Do not forget to save with the save icon in the lower right corner.

### Network

Optionally, you can configure your preferred network settings under **Network Interfaces**, such as DHCP, static IP, or disabling specific interfaces.

The initial configuration is now complete. You have a fully customized NVIDIA DGX Spark running MOS, headless, without telemetry.

The following sections describe one way to use AI on your device. This is not the only approach and is meant as a suggestion based on my own setup. Feel free to adapt or replace these steps with something else that fits your needs better.

## Installing llama-swap (optional)

You can now continue by installing additional software such as llama-swap from the MOS Hub.

1. Go to **MOS Hub** and refresh the repositories. You can set up a refresh schedule and enable automatic initial updates in **Settings** → **MOS Hub**.
2. Search for `llama-swap` and click **Install**.
3. After you receive the notification that the installation was successful, go to **Plugins** → **llama-swap**.
4. Set the install path. I would recommend `/mnt/nvme/appdata/llama-swap`.
5. Select the port. Make sure it does not collide with another port on your machine. The default is 8080.
6. Enable **Auto-start on boot**.
7. Click **Save Settings**.

You can find an example configuration showing how I run llama-swap [here](https://github.com/ich777/mos-dgx10/blob/master/files/llama-swap-example.conf). Please note that in that file you have to specify the paths inside the Docker container. In my case I map everything from the host at `/mnt/nvme/models` into the container at `/models`.

Do not forget to save your config with the **Save Config** button at the very bottom of the page. This will also restart the service.

### Automatic Docker image updates

Since I only update the containers through a cron script, I would recommend setting one up as well.

Go to **Settings** → **Cron Jobs** and click the plus icon in the lower right corner.

- Enable the switch
- **Name:** `Update Docker Images`
- **Schedule:** `40 3 * * 6` (this runs once a week, every Saturday at 3:40 AM)

You can of course change the schedule to your preference. In the script field, copy and paste the contents of [this script](https://github.com/ich777/mos-dgx10/blob/master/files/cronjob_update_containers.sh).

![Cron job configuration](https://github.com/ich777/mos-dgx10/blob/master/images/cron_job.png)

With this setup all your Docker containers will be updated once per week. You can run it more often if you like.

## Setup LXC Kernel Compilation

This section covers setting up an LXC container for compiling the kernel. This will also compile the NVIDIA 580.x driver with the kernel. If you have already compiled the same kernel before, the script will only recompile the driver, for example when a new driver version comes out.

In MOS go to **LXC** and click the plus icon in the lower right corner.

- **Name:** `KernelCompilation`
- **Distribution:** Devuan
- **Release:** Excalibur
- **Architecture:** arm64
- **Start after Creation:** Enabled

Click Create.

![Create LXC container](https://github.com/ich777/mos-dgx10/blob/master/images/lxc_create_container.png)

After the container has been created, click on the container icon and select terminal. Paste the following block in one go:

```bash
echo -e "HOME=/root\ncd /root" >> /root/.bashrc
su root
apt-get update
apt-get install wget nano curl
apt-get -y upgrade
apt-get -y autoremove
wget -q -O /root/compile.sh https://docs.mos-official.net/docs/Installation/Create-Bootable-Media
chmod +x /root/compile.sh
wget -q -O /root/config_arm_spark https://github.com/ich777/mos-dgx10/raw/refs/heads/master/lxc/config_arm_spark
```

The container is now set up and ready to build the kernel. When you want to build a new kernel, start the container, open a terminal and run:

```bash
su root
./compile.sh 6.18.55
```

This will compile the kernel for version 6.18.55. You can change the version to your preferred one. Please note that the script may prompt you to accept new kernel configuration options.

After the compilation finishes you will find the kernel image and driver together with their md5 sums in the output directory. On the host this will be located at `/mnt/nvme/system/lxc/KernelCompilation/rootfs/root/output/KERNELVERSION`.

Copy the image, driver and their md5 sums to `/boot` on your host. Also copy the `6.18.55-mos` directory (which contains the NVIDIA driver) to `/boot/optional/drivers/nvidia-driver`. The old driver for the old kernel will be deleted on reboot. If you are only upgrading the driver you can delete the `6.18.55-mos` directory. After that you can reboot or upgrade your system.

If you are upgrading your system, please be aware that you should never update the kernel from the default MOS release. Disable the kernel update option:

![Disable kernel update](https://github.com/ich777/mos-dgx10/blob/master/images/update.png)

Note: if you have already updated the MOS default release kernel, do not panic. As long as you have not rebooted you are still on the old kernel. Simply copy the files again or trigger the compilation once more.

The container will always produce this file structure:

```
output/
└── 6.18.55/
    ├── image
    ├── image.md5
    ├── drivers
    ├── drivers.md5
    ├── 6.18.55-mos.tar.xz
    ├── 6.18.55-mos.tar.xz.md5
    └── 6.18.55-mos/
        ├── nvidia-opensource_580.178.04-1+mos_amd64.deb
        └── nvidia-opensource_580.178.04-1+mos_amd64.deb.md5
```

## Updating firmware

This section covers manually updating the firmware for your DGX10/GX10 device. You will need to download the firmware archive from your manufacturer's support site first. The update process is manual and must be done one file at a time. It is recommended to store the extracted firmware files on a persistent storage location such as `/mnt/nvme/update` and copy them from there during the update process.

A detailed script with the full procedure can be found [here](https://github.com/ich777/mos-dgx10/blob/master/files/custom_firmware_update.sh). Please read it through once before starting, as it contains important notes and the exact order in which the firmware files must be applied.

### Download the script

Open a Terminal in MOS and run:

```bash
mkdir -p /mnt/nvme/update
wget -q -O /mnt/nvme/update/custom_firmware_update.sh https://github.com/ich777/mos-dgx10/raw/refs/heads/master/files/custom_firmware_update.sh
```

### Update procedure

For each firmware file (starting with file 1 and continuing after each reboot), run the preparation steps first:

```bash
yes | apt update
yes | apt install efivar
```

Then continue with:

1. Mount the EFI partition:
   ```bash
   mkdir -p /tmp/efi
   mount /dev/nvme0n1p1 /tmp/efi
   mkdir -p /tmp/efi/EFI/UpdateCapsule
   ```

2. Copy the firmware file from your persistent storage to `/tmp/efi/EFI/UpdateCapsule`. Make sure to check that the directory was empty before, which confirms the previous update was successful.

3. Trigger the update and reboot:
   ```bash
   sync
   umount /tmp/efi
   printf '\x04\x00\x00\x00\x00\x00\x00\x00' > /tmp/set_cap_flag.bin
   efivar --print --name "8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications"
   efivar -w --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications -f /tmp/set_cap_flag.bin
   efivar --print --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-OsIndications"
   reboot
   ```

4. After the reboot, repeat the process with the next firmware file.

The firmware files must be applied in a specific order with each update. The exact filenames and versions will change with each firmware release, so always refer to the downloaded archive for the current names. The [update script](https://github.com/ich777/mos-dgx10/blob/master/files/custom_firmware_update.sh) contains detailed notes on the process and will help guide you through each step.

### Verify firmware update

After all firmware files have been applied, you can verify that the updates were successful:

```bash
yes | apt update
yes | apt install fwupd
fwupdtool get-devices --show-all
```

---

This README was partially created with AI assistance and has been reviewed by a human.
