#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2019 Shivam Kumar Jha <jha.shivam3@gmail.com>
#
# Helper functions

# Store project path
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"

# Create some folders
mkdir -p "$PROJECT_DIR/dumps/" "$PROJECT_DIR/working"

# clean up
if [ "$1" == "y" ]; then
    rm -rf $PROJECT_DIR/working/*
fi

# set common var's
GITHUB_EMAIL="$(git config --get user.email)"
GITHUB_USER="$(git config --get user.name)"
[[ -z "$DUMMYDT" ]] && DUMMYDT="n"
[[ -z "$DUMPYARA" ]] && DUMPYARA="n"
[[ -z "$VERBOSE" ]] && VERBOSE="y"
export LC_ALL=C make

function dlrom() {
    mkdir -p ${PROJECT_DIR}/input
    cd ${PROJECT_DIR}/input
    if echo ${URL} | grep "https://drive.google.com/" && [[ ! -z "$(which gdrive)" ]]; then
        rm -rf ${PROJECT_DIR}/input/*
        FILE_ID="$(echo "${URL:?}" | sed -Er -e 's/https.*id=(.*)/\1/' -e 's/https.*\/d\/(.*)\/(view|edit)/\1/' -e 's/(.*)(&|\?).*/\1/')"
        gdrive download "$FILE_ID" || { echo "Download failed!"; }
        find ${PROJECT_DIR}/input -name "* *" -type f | rename 's/ /_/g'
        URL=$( ls -d $PWD/* )
    elif echo ${URL} | grep "https://mega.nz/" && [[ -e "/usr/bin/megadl" ]]; then
        rm -rf ${PROJECT_DIR}/input/*
        megadl "${URL}" || { echo "Download failed!"; }
        find ${PROJECT_DIR}/input -name "* *" -type f | rename 's/ /_/g'
        URL=$( ls -d $PWD/* )
    else
        FILE="$(echo ${URL##*/} | sed "s| |_|g" )"
        rm -rf $PROJECT_DIR/input/${FILE}
        aria2c -x 16 ${URL} -d ${PROJECT_DIR}/input -o ${FILE} || { echo "Download failed!"; }
        find ${PROJECT_DIR}/input -name "* *" -type f | rename 's/ /_/g'
        URL=$PROJECT_DIR/input/${FILE}
    fi
}
