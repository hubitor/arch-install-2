#!/bin/bash
#
# based on https://gist.github.com/sch1zo/5653983
# with input from http://blog.fabio.mancinelli.me/2012/12/28/Arch_Linux_on_BTRFS.html
#
tmp=`dirname $0`
BASE=`realpath $tmp/..`
echo $BASE

pause(){
  read -p "$*"
}

setup_btrfs(){
  local device=$1 ; shift 1
  # mount btrfs root
  # mkfs.btrfs -f -L "Debian" $device
  mkdir -p /mnt/btrfs-root
  mount -o defaults,relatime,discard,ssd,compress=lzo,autodefrag $device /mnt/btrfs-root

  # setup btrfs layout/subvolumes
  mkdir -p /mnt/btrfs-root/__snapshot
  mkdir -p /mnt/btrfs-root/__current
  for sub in "$@" ; do
    btrfs subvolume create /mnt/btrfs-root/__current/$sub
  done
}

mount_subvol(){
# mount __current/ROOT and create the mount points for mounting the other subvolumes
  local device=$1 ; shift 1
  #mkdir -p /mnt/btrfs-current
  mount -o defaults,relatime,discard,ssd,compress=lzo,subvol=__current/ROOT $device /target

  # mount the other subvolumes on the corresponding mount points
  for sub in "$@" ; do
  mkdir -p /target/$sub
    mount -o defaults,relatime,discard,ssd,compress=lzo,autodefrag,subvol=__current/$sub $device /target/$sub
  done

}

setup_boot(){
  # mount /boot
  mkdir -p /target/boot
  mount $1 /target/boot
  mkdir -p /target/boot/efi
  mount $2 /target/boot/efi
}

make_fs(){
  echo "make_fs"
  #Unmount the existing mount points because we will be reusing them. The Debian
  #installer will install into whatever is mounted as /target.
  umount /target/boot/efi
  umount /target/boot
  umount /target
  setup_btrfs $2 ROOT home opt var data
  mount_subvol $2 home opt var data
  setup_boot $1 $3
  # move the few files that the installer already wrote to the new target
  mv /mnt/btrfs-root/etc /target/
  mv /mnt/btrfs-root/media /target/
  umount /mnt/btrfs-root
}


read -p "efi device(/dev/sda1):" efi_device
if [[ -z "$efi_device" ]]; then
  efi_device='/dev/sda1'
fi

read -p "boot device(/dev/sda2):" boot_device
if [[ -z "$boot_device" ]]; then
  boot_device='/dev/sda2'
fi

read -p "root device(/dev/sda3):" root_device
if [[ -z "$root_device" ]]; then
  root_device='/dev/sda3'
fi

make_fs $boot_device $root_device $efi_device
echo "#UUID=... /run/btrfs-root btrfs rw,nodev,nosuid,noexec,relatime,ssd,discard,space_cache 0 0" >> /target/etc/fstab
cat /etc/mtab >> /target/etc/fstab
nano /target/etc/fstab


