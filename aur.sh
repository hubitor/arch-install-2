#!/bin/bash

TMP_DIR=/opt/tmp
cd $TMP_DIR
tar -xvzf $1.tar.gz
cd $1
sudo -u nobody makepkg -f --noconfirm -si

