#!/bin/bash

TMP_DIR=/opt/tmp
cd $TMP_DIR
tar -xvzf $1.tar.gz
cd $1
makepkg -f --asroot -si

