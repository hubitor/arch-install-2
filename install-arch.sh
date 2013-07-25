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

refresh_pacman() {
  echo "refresh pacman"
  pacman -Sy
  pacman -S --noconfirm reflector
  reflector -f 6 -l 6 --save /etc/pacman.d/mirrorlist
  pacman -Syy
}

setup_LUKS(){
  local device=$1
  echo $device
  cryptsetup luksFormat $device
  cryptsetup luksOpen $device cryptroot
}

setup_btrfs(){
  local device=$1 ; shift 1
  # format and mount btrfs root
  mkfs.btrfs -f -L "Arch Linux" $device
  mkdir /mnt/btrfs-root
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
  mkdir -p /mnt/btrfs-current
  mount -o defaults,relatime,discard,ssd,nodev,compress=lzo,subvol=__current/ROOT $device /mnt/btrfs-current

  # mount the other subvolumes on the corresponding mount points
  for sub in "$@" ; do
	mkdir -p /mnt/btrfs-current/$sub
    mount -o defaults,relatime,discard,ssd,nodev,nosuid,compress=lzo,autodefrag,subvol=__current/$sub $device /mnt/btrfs-current/$sub
  done

  # var/lib is special
  mkdir -p /mnt/btrfs-root/__current/ROOT/var/lib
  mount -o defaults,relatime,discard,ssd,nodev,nosuid,compress=lzo,autodefrag,subvol=__current/var $device /mnt/btrfs-current/var
  mkdir -p /mnt/btrfs-current/var/lib
  mount --bind /mnt/btrfs-root/__current/ROOT/var/lib /mnt/btrfs-current/var/lib
  #pause
}

setup_boot(){
  # format and mount /boot
  mkfs.ext4 $1
  mkdir -p /mnt/btrfs-current/boot
  mount $1 /mnt/btrfs-current/boot
}

make_fs(){
  echo "make_fs"
  setup_btrfs $2 ROOT home opt var data
  mount_subvol $2 home opt data var
  setup_boot $1
}

bootstrap_arch(){
  echo "bootstrap"
  pacstrap /mnt/btrfs-current base base-devel grub-bios os-prober mtools gptfdisk
  genfstab -U -p /mnt/btrfs-current >> /mnt/btrfs-current/etc/fstab
  echo "adding special handling for /var/lib"
  echo "#UUID=...	/run/btrfs-root	btrfs rw,nodev,nosuid,noexec,relatime,ssd,discard,space_cache 0 0" >> /mnt/btrfs-current/etc/fstab
  echo "#/run/btrfs-root/__current/ROOT/var/lib		/var/lib	none bind 0 0" >> /mnt/btrfs-current/etc/fstab
  vi /mnt/btrfs-current/etc/fstab

  read -p "hostname:(arch)" hostname
  if [[ -z "$hostname" ]]; then
    hostname='arch'
  fi
  echo $hostname > /mnt/btrfs-current/etc/hostname
  #enable en_US.UTF-8
  vi /mnt/btrfs-current/etc/locale.gen
  arch-chroot /mnt/btrfs-current locale-gen
  echo LANG=en_US.UTF-8 > /mnt/btrfs-current/etc/locale.conf
  arch-chroot /mnt/btrfs-current ln -s /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
  arch-chroot /mnt/btrfs-current hwclock --systohc --utc
}

add_encrypt_hook(){
  sed -i '/^HOOKS/ s/filesystems/encrypt filesystems/' /mnt/btrfs-current/etc/mkinitcpio.conf
  arch-chroot /mnt/btrfs-current mkinitcpio -p linux
}

setup_grub(){
  local encrypt=$1 root=$2
  if $encrypt ; then
    sed -i "/GRUB_CMDLINE_LINUX=/ c\GRUB_CMDLINE_LINUX=\\\"cryptdevice=${root}:cryptroot:allow-discards\\\"" /mnt/btrfs-current/etc/default/grub
  fi

  arch-chroot /mnt/btrfs-current grub-install --target=i386-pc --recheck /dev/sda
  arch-chroot /mnt/btrfs-current grub-mkconfig -o /boot/grub/grub.cfg
}

setup_aur(){
  local proxy=$1 tmp_dir=/opt/tmp
  mkdir -p /mnt/btrfs-current/$tmp_dir
  wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/aur.sh https://raw.github.com/seanvk/arch-install/master/aur.sh
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm expac yajl
  if $proxy ; then
    wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/cower.tar.gz https://raw.github.com/seanvk/arch-install/master/cower.tar.gz
    wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/packer.tar.gz https://raw.github.com/seanvk/arch-install/master/packer.tar.gz
  else
    wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/cower.tar.gz https://aur.archlinux.org/packages/co/cower/cower.tar.gz
    wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/packer.tar.gz https://aur.archlinux.org/packages/pa/packer/packer.tar.gz
  fi
  arch-chroot /mnt/btrfs-current sh $tmp_dir/aur.sh cower
  arch-chroot /mnt/btrfs-current sh $tmp_dir/aur.sh packer
  rm -r /mnt/btrfs-current/$tmp_dir
}

setup_pacman(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm reflector
  arch-chroot /mnt/btrfs-current reflector -f 6 -l 6 --save /etc/pacman.d/mirrorlist
  arch-chroot /mnt/btrfs-current packer -S powerpill
  arch-chroot /mnt/btrfs-current pacman -Syy
}

install_base_apps(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm sudo git gvim curl tmux zsh htop \
 openssh openssl dbus wget bc rsync wireless_tools wpa_supplicant wpa_actiond dialog btrfs-progs
}
install_x(){
  # install xserver, common stuff
  read -p "video-driver(xf86-video-intel)" VIDEO
  if [[ -z "$VIDEO" ]]; then
    VIDEO='xf86-video-intel'
  fi
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm xorg-server xorg-server-utils xorg-xinit \
mesa xf86-input-synaptics $VIDEO ttf-ubuntu-font-family ttf-liberation ttf-dejavu xorg-twm xorg-xclock xterm
}

install_gnome(){
  install_x
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm gnome gnome-extra gnome-tweak-tool gdm
}

install_apps(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm cpupower \
  chromium rdesktop nss vlc bash-completion pm-utils \
  laptop-mode-tools hdparm gvim meld \
  avahi nss-mdns fuse libva-intel-driver ntp deja-dup \
  cups cronie
}

setup_users(){
  echo "set rootpw:"
  arch-chroot /mnt/btrfs-current passwd
  read -p "default user:(seanvk)" user
  if [[ -z "$user" ]]; then
    user='seanvk'
  fi
  echo "create user $user"
  arch-chroot /mnt/btrfs-current useradd -m -g users -G wheel,adm,audio,optical,video,storage,lp,disk -s /bin/bash $user
  echo "set user pw:"
  arch-chroot /mnt/btrfs-current passwd $user
  arch-chroot /mnt/btrfs-current visudo
}

enable_services(){
  # enable systemd stuff
  arch-chroot /mnt/btrfs-current systemctl enable gdm.service
  arch-chroot /mnt/btrfs-current systemctl enable NetworkManager.service
  arch-chroot /mnt/btrfs-current systemctl enable cpupower.service
  arch-chroot /mnt/btrfs-current systemctl enable sshd.service
  arch-chroot /mnt/btrfs-current systemctl enable ntpd.service
  arch-chroot /mnt/btrfs-current systemctl enable avahi-daemon.service
  arch-chroot /mnt/btrfs-current systemctl enable laptop-mode.service
  arch-chroot /mnt/btrfs-current systemctl enable cups.service
  arch-chroot /mnt/btrfs-current systemctl enable cronie.service
}

# get some stuff from aur
install_aur_pkgs(){
  arch-chroot /mnt/btrfs-current packer -S sublime-text-nightly dropbox lastpass-pocket
}
install_zramswap(){
  arch-chroot /mnt/btrfs-current packer -S zramswap
  arch-chroot /mnt/btrfs-current systemctl enable zramswap.service
}

read -p "proxy? (y/N)?"
if [[ $REPLY == [yY] ]] ; then
  echo "use proxy"
  proxy=true
  read -p "http_proxy:" http_proxy_field
  read -p "https_proxy:" https_proxy_field
else
  echo "no proxy"
  proxy=false
  http_proxy_field=
  https_proxy_field=
fi

export http_proxy=${http_proxy_field}
export https_proxy=${https_proxy_field}


read -p "boot device(/dev/sda2):" boot_device
if [[ -z "$boot_device" ]]; then
  boot_device='/dev/sda2'
fi

read -p "root device(/dev/sda3):" root_device
if [[ -z "$root_device" ]]; then
  root_device='/dev/sda3'
fi
root_raw=$root_device

read -p "encrypt? (y/N)?"
if [[ $REPLY == [yY] ]] ; then
  echo "use encrypt"
  encrypt=true
else
  echo "no encryption"
  encrypt=false
fi

if $encrypt ; then
  setup_LUKS $root_device
  root_device=/dev/mapper/cryptroot
fi
echo "boot: $boot_device | root: $root_device"

make_fs $boot_device $root_device
refresh_pacman
bootstrap_arch
if $encrypt ; then
  add_encrypt_hook
fi
setup_grub $encrypt $root_raw
setup_aur $proxy
setup_pacman
install_base_apps
setup_users

read -p "gnome? (y/N)"
if [[ $REPLY == [yY] ]] ; then
  install_gnome
  install_apps
  install_aur_pkgs
  enable_services
else
  arch-chroot /mnt/btrfs-current systemctl enable sshd.service
  arch-chroot /mnt/btrfs-current systemctl enable dhcpcd.service
fi

read -p "zramswap? (y/N)?"
if [[ $REPLY == [yY] ]] ; then
  install_zramswap
fi

read -p "umount?(Y/n)?"
if [[ $REPLY == [nN] ]] ; then
  exit 0
fi
umount /mnt/btrfs-current/boot
umount /mnt/btrfs-current/home
umount /mnt/btrfs-current/opt
umount /mnt/btrfs-current/var/lib
umount /mnt/btrfs-current/var
umount /mnt/btrfs-current/data
umount /mnt/btrfs-current/
umount /mnt/btrfs-root
