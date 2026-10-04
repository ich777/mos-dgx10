#!/bin/bash
if [ -z "$1" ] ; then
  echo "Please specify the Kernel version"
  exit 1
fi

DEFAULT_DIR=/opt/mos-kernel
BUILD_DIR=${DEFAULT_DIR}/build
WORK_DIR=${DEFAULT_DIR}
OUTPUT_DIR=/root/output

apt-get update
apt-get -y install build-essential flex bison libncurses-dev libssl-dev libelf-dev bc dwarves kmod squashfs-tools rsync git cpio xz-utils zip python3 tidy
apt-get -y upgrade
apt-get -y autoremove

# Define Kernel Version
KERNEL_V=$1

rm -rf $WORK_DIR/$KERNEL_V $BUILD_DIR/$KERNEL_V /lib/modules /lib/firmware
mkdir -p $BUILD_DIR $WORK_DIR/$KERNEL_V $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos $BUILD_DIR/$KERNEL_V /lib/modules /lib/firmware

# Safety check for Kernel versions ending with 0
if [ "${KERNEL_V##*.}" == "0" ]; then
  DL_KERNEL_V="${KERNEL_V%.*}"
else
  DL_KERNEL_V=$KERNEL_V
fi

if [ ! -f "$OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos_arm64.tar.xz" ] ; then
  # Download and extract Kernel
  cd $BUILD_DIR
  wget -O $BUILD_DIR/linux-$KERNEL_V.tar.xz https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_V%%.*}.x/linux-$DL_KERNEL_V.tar.xz;
  mkdir -p $BUILD_DIR/$KERNEL_V
  tar -C $BUILD_DIR/$KERNEL_V --strip-components=1 -xf $BUILD_DIR/linux-$KERNEL_V.tar.xz
  cd $BUILD_DIR/$KERNEL_V

  cp /root/config_arm_spark $BUILD_DIR/$KERNEL_V/.config

  make oldconfig

  cp /root/config_arm_spark /root/.config_arm_spark.old
  cp $BUILD_DIR/$KERNEL_V/.config /root/config_arm_spark

  make -j$(nproc --all)

  # Copy image to output directory
  cp $BUILD_DIR/$KERNEL_V/arch/arm64/boot/Image $OUTPUT_DIR/$KERNEL_V/image

  # Save Kernel
  echo "Creating Kernel archive..."
  XZ_OPT="-9 -T0" tar -cJf $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos_arm64.tar.xz .

  # Install Modules to /lib/modules
  make -j$(nproc --all) modules_install

  # Build Nvidia Hotplug module
  rm -rf /tmp/nvidia-hotplug-module
  cp -R /root/nvidia-hotplug-module /tmp/nvidia-hotplug-module
  make -C $BUILD_DIR/$KERNEL_V M=/tmp/nvidia-hotplug-module modules
  mkdir -p /lib/modules/$KERNEL_V-mos/kernel/drivers/platform/arm64/nvidia
  strip --strip-debug /tmp/nvidia-hotplug-module/mtk-pcie-hotplug.ko
  xz -9 -C crc32 /tmp/nvidia-hotplug-module/mtk-pcie-hotplug.ko
  cp /tmp/nvidia-hotplug-module/mtk-pcie-hotplug.ko.xz /lib/modules/$KERNEL_V-mos/kernel/drivers/platform/arm64/nvidia/

  # Clone Linux Firmware
  cd $WORK_DIR
  git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git $WORK_DIR/firmware-source
  cd $WORK_DIR/firmware-source
  FW_COMMIT=$(git rev-parse HEAD)
  FW_COMMIT_SHORT=$(git rev-parse --short HEAD)
  $WORK_DIR/firmware-source/copy-firmware.sh $WORK_DIR/linux-firmware

  # Set MODULE_PATH variable
  cd $WORK_DIR
  MODULE_PATH="/lib/modules/${KERNEL_V}-mos"

  # Generate file list
  find "$MODULE_PATH" -name "*.ko*" -exec modinfo {} \; 2>/dev/null | \
    grep "^firmware:" | cut -d: -f2- | sed 's/^[[:space:]]*//' | sort -u \
    > "$WORK_DIR/required_firmware"

  # Make sure to copy all files including symlinks
  while read fw; do
    full="$WORK_DIR/linux-firmware/$fw"
    if [ -L "$full" ]; then
      echo "$fw" >> "$WORK_DIR/required_firmware_complete"
      target=$(readlink -f "$full")
      rel="${target#$WORK_DIR/linux-firmware/}"
      echo "$rel" >> "$WORK_DIR/required_firmware_complete"
    elif [ -f "$full" ]; then
      echo "$fw" >> "$WORK_DIR/required_firmware_complete"
    else
      echo "Missing Firmware: $fw" >&2
    fi
  done < "$WORK_DIR/required_firmware"

  # Remove duplicates
  sort -u -o "$WORK_DIR/required_firmware_complete" "$WORK_DIR/required_firmware_complete"

  # Copy firmware files
  rsync -av --files-from="$WORK_DIR/required_firmware_complete" "$WORK_DIR/linux-firmware/" /lib/firmware/

  # Copy over Modules and Firmware files and make sure to save attributes
  cp -a /lib/modules $WORK_DIR/$KERNEL_V/
  cp -a /lib/firmware $WORK_DIR/$KERNEL_V/
  rm -rf $WORK_DIR/$KERNEL_V/lib/modules/${KERNEL_V}-mos/build
  cd $WORK_DIR/$KERNEL_V

  # Copy licenses and copying to drivers
  mkdir -p $WORK_DIR/$KERNEL_V/usr/share/doc/linux/LICENSES/preferred
  cp $BUILD_DIR/$KERNEL_V/COPYING $WORK_DIR/$KERNEL_V/usr/share/doc/linux/COPYING
  cp $BUILD_DIR/$KERNEL_V/LICENSES/preferred/* $WORK_DIR/$KERNEL_V/usr/share/doc/linux/LICENSES/preferred/

  # Create drivers image
  mksquashfs $WORK_DIR/$KERNEL_V $OUTPUT_DIR/$KERNEL_V/drivers -noappend -comp xz

  # Create md5 sums
  md5sum $OUTPUT_DIR/$KERNEL_V/image | awk '{print $1}' > $OUTPUT_DIR/$KERNEL_V/image.md5
  md5sum $OUTPUT_DIR/$KERNEL_V/drivers | awk '{print $1}' > $OUTPUT_DIR/$KERNEL_V/drivers.md5
  md5sum $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos_arm64.tar.xz | awk '{print $1}' > $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos_arm64.tar.xz.md5
else
  mkdir -p $BUILD_DIR/$KERNEL_V
  tar -C $BUILD_DIR/$KERNEL_V/ -xf "$OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos_arm64.tar.xz"
  cd $BUILD_DIR/$KERNEL_V
  make -j$(nproc --all) modules_install
fi

# Build Nvidia Driver
DRIVER_NAME=nvidia
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

RAW_DATA=$(wget -qO- https://forums.developer.nvidia.com/t/current-graphics-driver-releases/28500 | tidy -quiet -wrap 4096 2>/dev/null || true)
OPENSOURCE_DRV_V_PKG=$(echo "${RAW_DATA}" | grep -i -A1 '>Legacy releases' | grep -oE '\b[0-9]+\.[0-9]+(\.[0-9]+)?\b' | tail -1)
if [ -z "$OPENSOURCE_DRV_V_PKG" ] ; then
  echo "ERROR: Nvidia driver version empty"
  exit 1
fi
#OPENSOURCE_DRV_V_PKG=580.159.03
KERNEL_DIR=$BUILD_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Get latest versions
LIBNVIDIA_CONTAINER_JSON="$(curl -s https://api.github.com/repos/mos-nas/mos-libnvidia-container/releases/latest)"
LIBNVIDIA_CONTAINER_V="$(echo "$LIBNVIDIA_CONTAINER_JSON" | jq -r '.tag_name' | sed 's/^v//')"
CONTAINER_TOOLKIT_JSON="$(curl -s https://api.github.com/repos/mos-nas/mos-nvidia-container-toolkit/releases/latest)"
CONTAINER_TOOLKIT_V="$(echo "$CONTAINER_TOOLKIT_JSON" | jq -r '.tag_name' | sed 's/^v//')"

wget -O $DRIVER_BUILD_DIR/nvidia-container-toolkit_${CONTAINER_TOOLKIT_V}+mos_arm64.deb https://github.com/mos-nas/mos-nvidia-container-toolkit/releases/download/$CONTAINER_TOOLKIT_V/nvidia-container-toolkit_${CONTAINER_TOOLKIT_V}-1+mos_arm64.deb
wget -O $DRIVER_BUILD_DIR/libnvidia-container_${LIBNVIDIA_CONTAINER_V}-1+mos_arm64.deb https://github.com/mos-nas/mos-libnvidia-container/releases/download/$LIBNVIDIA_CONTAINER_V/libnvidia-container_${LIBNVIDIA_CONTAINER_V}-1+mos_arm64.deb

NV_PROPRIETARY="--kernel-module-type=open"

# Change directory and remove old directories
cd $DRIVER_BUILD_DIR
rm -rf $DRIVER_PACKAGE_DIR /lib/firmware/nvidia

wget -q -nc --show-progress --progress=bar:force:noscroll -O $DRIVER_BUILD_DIR/NVIDIA_v${OPENSOURCE_DRV_V_PKG}.run https://download.nvidia.com/XFree86/Linux-aarch64/${OPENSOURCE_DRV_V_PKG}/NVIDIA-Linux-aarch64-${OPENSOURCE_DRV_V_PKG}.run

# Make driver executable and create directories
chmod +x $DRIVER_BUILD_DIR/NVIDIA_v${OPENSOURCE_DRV_V_PKG}.run
mkdir -p $DRIVER_PACKAGE_DIR/usr/lib/xorg/modules/{drivers,extensions} $DRIVER_PACKAGE_DIR/usr/lib/aarch64-linux-gnu $DRIVER_PACKAGE_DIR/usr/bin $DRIVER_PACKAGE_DIR/etc $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/video $DRIVER_PACKAGE_DIR/lib/firmware

$DRIVER_BUILD_DIR/NVIDIA_v${OPENSOURCE_DRV_V_PKG}.run --kernel-source-path=$KERNEL_DIR \
  --no-precompiled-interface \
  --disable-nouveau \
  --x-prefix=$DRIVER_PACKAGE_DIR/usr \
  --x-library-path=lib/aarch64-linux-gnu \
  --x-module-path=$DRIVER_PACKAGE_DIR/usr/lib/xorg/modules \
  --opengl-prefix=$DRIVER_PACKAGE_DIR/usr \
  --installer-prefix=$DRIVER_PACKAGE_DIR/usr \
  --utility-prefix=$DRIVER_PACKAGE_DIR/usr \
  --documentation-prefix=$DRIVER_PACKAGE_DIR/usr \
  --application-profile-path=share/nvidia \
  --proc-mount-point=$DRIVER_PACKAGE_DIR/proc \
  --kernel-install-path=$DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/video \
  --no-x-check \
  --no-nouveau-check \
  --no-systemd \
  --skip-depmod \
  --skip-module-load \
  --no-backup \
  --j$(nproc --all) \
  --allow-installation-with-running-driver \
  ${NV_PROPRIETARY} --silent

cp -R /lib/firmware/nvidia $DRIVER_PACKAGE_DIR/lib/firmware/

cp /usr/bin/nvidia-modprobe $DRIVER_PACKAGE_DIR/usr/bin/
cp -R /etc/OpenCL $DRIVER_PACKAGE_DIR/etc/
cp -R /etc/vulkan $DRIVER_PACKAGE_DIR/etc/

# Fix for gbm symlink
cd $DRIVER_PACKAGE_DIR/usr/lib/aarch64-linux-gnu/gbm
rm -f nvidia-drm_gbm.so
ln -sf /usr/lib/aarch64-linux-gnu/libnvidia-allocator.so.1 nvidia-drm_gbm.so

mkdir -p $DRIVER_PACKAGE_DIR/usr/share/glvnd/egl_vendor.d $DRIVER_PACKAGE_DIR/usr/share/egl/egl_external_platform.d
cp /usr/share/glvnd/egl_vendor.d/*nvidia*.json $DRIVER_PACKAGE_DIR/usr/share/glvnd/egl_vendor.d/
cp /usr/share/egl/egl_external_platform.d/*nvidia*.json $DRIVER_PACKAGE_DIR/usr/share/egl/egl_external_platform.d/

# Add additional components
dpkg --root=$DRIVER_PACKAGE_DIR --install $DRIVER_BUILD_DIR/nvidia-container-toolkit_${CONTAINER_TOOLKIT_V}+mos_arm64.deb
dpkg --root=$DRIVER_PACKAGE_DIR --install $DRIVER_BUILD_DIR/libnvidia-container_${LIBNVIDIA_CONTAINER_V}-1+mos_arm64.deb


rm -rf $DRIVER_PACKAGE_DIR/var

mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: $DRIVER_NAME-opensource-driver
Version: $OPENSOURCE_DRV_V_PKG
Architecture: arm64
Maintainer: ich777
Description: ${DRIVER_NAME}-opensource drivers for MOS
EOF

cd $DRIVER_BUILD_DIR
dpkg-deb --build package $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos/${DRIVER_NAME}-opensource_${OPENSOURCE_DRV_V_PKG}-1+mos_amd64.deb

md5sum $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos/${DRIVER_NAME}-opensource_${OPENSOURCE_DRV_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $OUTPUT_DIR/$KERNEL_V/${KERNEL_V}-mos/${DRIVER_NAME}-opensource_${OPENSOURCE_DRV_V_PKG}-1+mos_amd64.deb.md5

rm -rf $WORK_DIR/firmware-source $WORK_DIR/linux-firmware $WORK_DIR/build $WORK_DIR/required_firmware $WORK_DIR/required_firmware_complete $WORK_DIR/$KERNEL_V /tmp/nvidia-hotplug-module
