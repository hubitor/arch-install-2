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
  pacman -S --noconfirm rsync reflector
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
  mkfs.btrfs -f -L "ArchLinux" $device
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
  mkfs.vfat -F32 $2
  mkdir -p /mnt/btrfs-current/boot
  mount $1 /mnt/btrfs-current/boot 
  mkdir -p /mnt/btrfs-current/boot/efi
  mount $2 /mnt/btrfs-current/boot/efi
}

make_fs(){
  echo "make_fs"
  setup_btrfs $3 ROOT home opt var data
  mount_subvol $3 home opt data
  setup_boot $1 $2
}

bootstrap_arch(){
  echo "bootstrap"
  pacstrap /mnt/btrfs-current base base-devel grub efibootmgr os-prober dosfstools mtools gptfdisk
  genfstab -U -p /mnt/btrfs-current >> /mnt/btrfs-current/etc/fstab
  echo "adding special handling for /var/lib"
  echo "#UUID=... /run/btrfs-root btrfs rw,nodev,nosuid,noexec,relatime,ssd,discard,space_cache 0 0" >> /mnt/btrfs-current/etc/fstab
  echo "#/run/btrfs-root/__current/ROOT/var/lib   /var/lib  none bind 0 0" >> /mnt/btrfs-current/etc/fstab
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
  else
    sed -i "/GRUB_CMDLINE_LINUX=/ c\GRUB_CMDLINE_LINUX=\\\"rootflags=subvol=__current/ROOT\\\"" /mnt/btrfs-current/etc/default/grub
  fi
  arch-chroot /mnt/btrfs-current modprobe efivars
  arch-chroot /mnt/btrfs-current modprobe dm-mod
  arch-chroot /mnt/btrfs-current grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch_grub --boot-directory=/boot/efi/EFI --recheck --debug
 
  arch-chroot /mnt/btrfs-current grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg
  arch-chroot /mnt/btrfs-current mkdir -p /boot/efi/EFI/boot
  arch-chroot /mnt/btrfs-current cp /boot/efi/EFI/arch_grub/grubx64.efi /boot/efi/EFI/boot/bootx64.efi
}

setup_aur(){
  if [[ "$proxy" == "false" ]] ; then
  local tmp_dir=/opt/tmp
  mkdir -p /mnt/btrfs-current/$tmp_dir
  wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/aur.sh https://raw.github.com/seanvk/arch-install/master/aur.sh
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm expac yajl
  gpg --recv-keys --keyserver hkp://pgp.mit.edu 1EB2638FF56C0C53
  wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/cower.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/cower.tar.gz
  wget --no-check-certificate -O /mnt/btrfs-current/$tmp_dir/pacaur.tar.gz https://aur.archlinux.org/cgit/aur.git/snapshot/pacaur.tar.gz
  arch-chroot /mnt/btrfs-current sh $tmp_dir/aur.sh cower
  arch-chroot /mnt/btrfs-current sh $tmp_dir/aur.sh pacaur
  rm -r /mnt/btrfs-current/$tmp_dir
  fi
}

setup_pacman(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm rsync reflector
  arch-chroot /mnt/btrfs-current reflector -f 6 -l 6 --save /etc/pacman.d/mirrorlist
  arch-chroot /mnt/btrfs-current pacaur -Sy powerpill
  arch-chroot /mnt/btrfs-current pacman -Syy
}

install_base_apps(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm sudo git vim curl tmux zsh htop \
 openssh openssl dbus wget bc wireless_tools wpa_supplicant wpa_actiond dialog btrfs-progs
 arch-chroot /mnt/btrfs-current pacman -S --noconfirm xdg-user-dirs
}
install_x(){
  # install xserver, common stuff
  read -p "video-driver(xf86-video-intel)" VIDEO
  if [[ -z "$VIDEO" ]]; then
    VIDEO='xf86-video-intel'
  fi
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm xorg-server xorg-xinit \
mesa xf86-input-synaptics $VIDEO adobe-source-sans-pro-fonts ttf-ubuntu-font-family ttf-liberation ttf-dejavu
}

install_kde(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm kde-meta kdeplasma-applets-plasma-nm network-manager-applet kdiff3
  arch-chroot /mnt/btrfs-current systemctl disable gdm.service
  arch-chroot /mnt/btrfs-current systemctl enable kdm.service
}

install_gnome(){
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm gnome gnome-extra gnome-tweak-tool
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm numix-themes breeze-icons
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm libreoffice-fresh gimp
  arch-chroot /mnt/btrfs-current systemctl disable kdm.service
  arch-chroot /mnt/btrfs-current systemctl enable gdm.service
}


install_apps(){
  
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm cpupower \
  rdesktop nss bash-completion elinks weechat dhclient
  
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm \
  gvim netkit-bsd-finger alsa-utils dnsutils rfkill offlineimap
  
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm avahi nss-mdns \
  fuse exfat-utils libva-intel-driver ntp acpid deja-dup python2-pyopenssl cracklib keychain
  
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm \
  cups ghostscript gsfonts libcups cronie firefox firefox-i18n-en-us arch-firefox-search archlinux-wallpaper
  
  arch-chroot /mnt/btrfs-current pacman -S --noconfirm openbsd-netcat tsocks linux-headers \
  dkms mercurial archlinux-themes-kdm gnupg
 
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
  arch-chroot /mnt/btrfs-current systemctl enable NetworkManager.service
  arch-chroot /mnt/btrfs-current systemctl enable cpupower.service
  arch-chroot /mnt/btrfs-current systemctl enable sshd.service
  arch-chroot /mnt/btrfs-current systemctl enable acpid.service
  arch-chroot /mnt/btrfs-current systemctl enable ntpd.service
  arch-chroot /mnt/btrfs-current systemctl enable avahi-daemon.service
  arch-chroot /mnt/btrfs-current systemctl enable org.cups.cupsd.service
  arch-chroot /mnt/btrfs-current systemctl enable cups.service
  arch-chroot /mnt/btrfs-current systemctl enable cronie.service
}

# get some stuff from aur
install_aur_pkgs(){
  arch-chroot /mnt/btrfs-current pacaur -Sy sublime-text-dev ttf-ms-fonts
  arch-chroot /mnt/btrfs-current pacaur -Sy mutt-patched python-zsi
}
install_zramswap(){
  arch-chroot /mnt/btrfs-current pacaur -Sy zramswap
  arch-chroot /mnt/btrfs-current systemctl enable zramswap.service
}

modprobe efivars
modprobe dm-mod

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

make_fs $efi_device $boot_device $root_device
refresh_pacman
bootstrap_arch
if $encrypt ; then
  add_encrypt_hook
else
  arch-chroot /mnt/btrfs-current mkinitcpio -p linux
fi
setup_grub $encrypt $root_raw
setup_aur $proxy
setup_pacman
install_base_apps
setup_users

read -p "Install a desktop environment? (y/N)"
if [[ $REPLY == [yY] ]] ; then
  install_x
  read -p "Install gnome? (y/N)"
  if [[ $REPLY == [yY] ]] ; then
    install_gnome
  fi
  read -p "Install kde? (y/N)"
  if [[ $REPLY == [yY] ]] ; then
    install_kde
  fi
  install_apps
  install_aur_pkgs
  enable_services
else
  arch-chroot /mnt/btrfs-current systemctl enable sshd.service
  arch-chroot /mnt/btrfs-current systemctl enable dhcpcd.service
fi

#read -p "zramswap? (y/N)?"
#if [[ $REPLY == [yY] ]] ; then
#  install_zramswap
#fi

# manually install efivars
#pause
#umount /sys/firmware/efi
#modprobe -r efivars
#modprobe efivars
#modprobe dm-mod
#efibootmgr -q -c -d /dev/sda -p 1 -w -L arch_grub -l '\EFI\arch_grub\grubx64.efi'

read -p "umount?(Y/n)?"
if [[ $REPLY == [nN] ]] ; then
  exit 0
fi
umount /mnt/btrfs-current/boot/efi
umount /mnt/btrfs-current/boot
umount /mnt/btrfs-current/home
umount /mnt/btrfs-current/opt
umount /mnt/btrfs-current/var/lib
umount /mnt/btrfs-current/var
umount /mnt/btrfs-current/data
umount /mnt/btrfs-current/
umount /mnt/btrfs-root
