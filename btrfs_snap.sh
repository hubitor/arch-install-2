#!/bin/bash

subvol=$1

if [[ ! -d "/run/btrfs-root" ]] ; then
	# Easy snapshots
	mkdir /run/btrfs-root
	mount /dev/mapper/cryptroot /run/btrfs-root
fi

DATE=`date "+%Y%m%d-%H%M%S"`
read -p "Comment: " COMMENT

echo "$DATE
$COMMENT" > /SNAPSHOT

btrfs subvolume snapshot -r /run/btrfs-root/__current/$1 /run/btrfs-root/__snapshot/$subvol@$DATE
btrfs subvolume delete /run/btrfs-root/__snapshot/LATEST
btrfs subvolume snapshot -r /run/btrfs-root/__snapshot/$subvol@$DATE /run/btrfs-root/__snapshot/LATEST

rm /SNAPSHOT
