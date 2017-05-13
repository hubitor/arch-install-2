#!/bin/bash

TMP_DIR=/opt/tmp
cd $TMP_DIR
tar -xvzf $1.tar.gz
chmod -R 777 $1
cd $1
sudo -u nobody makepkg -f --noconfirm -si
