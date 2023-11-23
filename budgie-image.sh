#!/usr/bin/env bash

CODENAME="jammy"
BASEIMAGE="$CODENAME-desktop-amd64.iso"
IMAGE="NETWORK-IMAGE.iso"
RELEASE="cdimage.ubuntu.com/ubuntu-budgie/jammy/daily-live/current/"
RELEASEIMAGE="$CODENAME-network-desktop-amd64.iso"
SHA256SUMS="SHA256SUMS"
MOUNT="/mnt/nm"
NAMESERVER="1.1.1.1"
LOGFILE="ubnm.log"

log () {
    LOGTIME=$(date "+%m-%d-%Y-%H:%M:%S")
    echo $1
    echo "${LOGTIME}: $1" >> $LOGFILE
}

# check if we have persmissions, and the correct packages are installed
if [ "$(id -u)" -ne 0 ]; then
  echo "You need to be root to run this."
  exit 1
fi

# Start in the script directory (and remember it for later)
cd ${0%/*}
SCRIPT_PATH=$(pwd)

rm -f ubnm.log
log "Running in $SCRIPT_PATH"

# If we have a successfully built image, instead of overwriting it,
# back it up by prepending a timestamp
if test -f "$RELEASEIMAGE.iso"; then
    log "Budgie image exists... backing up"
    mv $RELEASEIMAGE ${RELEASEIMAGE}.old
fi

# Download the latest image
log "Downloading image"
zsync http://${RELEASE}/${BASEIMAGE}.zsync
EXITCODE=$?
if [ $EXITCODE -ne 0 ]; then
    log "Error downloading image"
    exit 1
fi

# Let's grab the SHA256SUM and double check the base image is ok
# before we distribute an image based on it
wget https://${RELEASE}/${SHA256SUMS} -O $SHA256SUMS
log "Verifying Image"
if sha256sum -c $SHA256SUMS 2>&1 | grep OK; then
    log "Image successfully verified"
else
    log "Could not verify image. Bad SHA256SUM match"
    exit
fi

# Delete any possible incomplete temp image and copy the image to a temp
# so we don't modify the original and defeat the purpose of zsync
if [ -f "$IMAGE" ]; then
    rm $IMAGE
    log "Removing existing ${IMAGE}"
fi
if [ -f "$IMAGE" ]; then
    rm $IMAGE
    log "Removing existing ${IMAGE}"
fi
cp $BASEIMAGE $IMAGE

log "Uncompressing image"
7z x $IMAGE

# Set up the chroot environment
log "Creating mount"
#OFFSET=$(parted "$IMAGE" unit b print | grep "ext4" | awk '{ print substr($2,0,length($2)-1) }')
mkdir -p $MOUNT
mount -o loop $IMAGE $MOUNT
#cp seed.yaml $MOUNT/var/lib/snapd/seed/seed.yaml
#cp /usr/bin/qemu-arm-static $MOUNT/usr/bin/
cp setup-budgie.dontrun $MOUNT/usr/bin/setup-budgie.sh

# If we want to install any .debs, we can place them in the patches folder
# They will automatically be installed by the conversion script
cp patches/*.deb $MOUNT/tmp

chmod +x $MOUNT/usr/bin/setup-budgie.sh
echo "nameserver $NAMESERVER" > $MOUNT/run/systemd/resolve/stub-resolv.conf
# rm $MOUNT/run/systemd/resolve/stub-resolv.conf
# echo "nameserver $NAMESERVER" > tempconf.tmp
# cp tempconf.tmp $MOUNT/run/systemd/resolve/stub-resolv.conf
# rm tempconf.tmp
cd $MOUNT
log "Setting up chroot environment"
mount -t proc /proc proc/
mount --make-rslave proc/
mount --rbind /sys sys/
mount --make-rslave sys/
mount --rbind /dev dev/
mount --make-rslave dev/

# Create the image
log "Running conversion"
chroot $MOUNT /usr/bin/setup-budgie.sh
log "Conversion complete"

# Clean up the image
#rm $MOUNT/usr/bin/qemu-arm-static
rm $MOUNT/tmp/*

# Clean up local machine. Regardless, local machine will be in an unstable state after this
# and should ultimately be reboot on completion
log "Cleaning up chroot environment"
cd $SCRIPT_PATH
umount -l -R $MOUNT/dev
umount -l -R $MOUNT/sys
umount $MOUNT/proc
umount $MOUNT
rmdir $MOUNT

# Rename the temp image now that it is complete
mv $IMAGE $RELEASEIMAGE

# Next line will take a long time to recompress unless you are using a 16 core NVME based Ryzen 7 or better machine!
log "Compressing completed image"
xz -v -9 --threads=0 $RELEASEIMAGE

# We did all this with root permissions, give the user ownership back of their own files
chown ${SUDO_USER}:${SUDO_USER} * &>/dev/null

log "Build complete"
