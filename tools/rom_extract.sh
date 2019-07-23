#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2019 Shivam Kumar Jha <jha.shivam3@gmail.com>
#
# Helper functions

SECONDS=0

# Store project path
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null && pwd )"
cd $PROJECT_DIR

# Common stuff
source $PROJECT_DIR/tools/common_script.sh "y"

# Password
if [ -z "$1" ]; then
	read -p "Enter user password: " user_password
else
	user_password=$1
fi

# Create repo?
if [ -z "$2" ]; then
	read -p "Create repo (y/n): " create_repo
else
	create_repo=$2
fi

# Dependecies check
bash $PROJECT_DIR/tools/dependencies.sh "$user_password" > /dev/null 2>&1

# array variable storing potential partitions to be extracted
declare -a arr=("cust" "modem" "odm" "oem" "system" "vendor" "xrom")

clean_up()
{
	echo -e "${bold}${cyan}Unmounting images & performing cleanup.${nocol}"
	for i in "${arr[@]}"; do
		if [ -d working/$i/ ]; then
			echo $user_password | sudo -S umount -l working/$i/
		fi
	done
	rm -rf working/*
}

extract_subcomponent()
{
	if [ -e working/$ZIPDIR.new.dat.br ]; then
		echo -e "${bold}${cyan}Extracting working/${ZIPDIR}.new.dat.br${nocol}"
		brotli -d working/$ZIPDIR.new.dat.br
	fi

	if [ -e working/$ZIPDIR.new.dat ]; then
		echo -e "${bold}${cyan}Converting working/${ZIPDIR}.new.dat to working/${ZIPDIR}.img${nocol}"
		./tools/sdat2img/sdat2img.py working/$ZIPDIR.transfer.list working/$ZIPDIR.new.dat working/$ZIPDIR.img
	fi

	if [ -e working/$ZIPDIR.img ]; then
		echo -e "${bold}${cyan}Mounting working/${ZIPDIR}.img${nocol}"
		mkdir -p working/$ZIPDIR
		if [ "$IS_FASTBOOT" == "y" ] && [ "$ZIPDIR" != "modem" ]; then
			simg2img working/$ZIPDIR.img working/$ZIPDIR.ext4.img > /dev/null 2>&1
			echo $user_password | sudo -S mount -t ext4 -o loop working/$ZIPDIR.ext4.img working/$ZIPDIR/ > /dev/null 2>&1
		elif [ "$ZIPDIR" == "modem" ]; then
			echo $user_password | sudo -S mount -t vfat -o loop working/$ZIPDIR.img working/$ZIPDIR/ > /dev/null 2>&1
		else
			echo $user_password | sudo -S mount -t ext4 -o loop working/$ZIPDIR.img working/$ZIPDIR/ > /dev/null 2>&1
		fi
		echo $user_password | sudo -S chown -R $USER:$USER working/$ZIPDIR/ > /dev/null 2>&1
		echo $user_password | sudo -S chmod -R 777 working/$ZIPDIR/ > /dev/null 2>&1
	fi

	if [ -z "$(ls -A working/$ZIPDIR/)" ]; then
		echo -e "${bold}${red}Error! Extracting $ZIPDIR failed.${nocol}"
	fi
}

core()
{
# A/B
if [ -e working/payload.bin ]; then
	./tools/extract_android_ota_payload/extract_android_ota_payload.py working/payload.bin working/
fi

# Find modem
find working/ -name 'NON-HLOS.bin' -exec mv {} working/modem.img \;
if [ ! -e working/modem.img ]; then
	find working/ -name '*modem*' -exec mv {} working/modem.img \;
fi

# Extraction
for i in "${arr[@]}"; do
	if [ -e working/$i.img ] || [ -e working/$i.new.dat ] || [ -e working/$i.new.dat.br ] ; then
		ZIPDIR=$i
		extract_subcomponent
	fi
done

# set variables
source $PROJECT_DIR/tools/rom_vars.sh "$PROJECT_DIR/working" > /dev/null 2>&1

# Copy to device folder
if [ ! -d dumps/$DEVICE ]; then
	mkdir -p dumps/$DEVICE
else
	echo -e "${bold}${cyan}Removing previously extracted files in dumps/${DEVICE}${nocol}"
	rm -rf dumps/$DEVICE/*
fi

# boot.img operations
find working/ -name 'boot.img' -exec mv {} working/bootdevice.img \;
if [ -e working/bootdevice.img ]; then
	# Extract kernel
	./tools/mkbootimg_tools/mkboot working/bootdevice.img dumps/$DEVICE/boot > /dev/null 2>&1
	mv dumps/$DEVICE/boot/kernel dumps/$DEVICE/boot/Image.gz-dtb
	echo -e "${bold}${cyan}boot_info: $(ls dumps/$DEVICE/boot/img_info)${nocol}"
	echo -e "${bold}${cyan}Prebuilt kernel: $(ls dumps/$DEVICE/boot/Image.gz-dtb)${nocol}"
	# Extract dtb
	echo -e "${bold}${cyan}Extracting dtb${nocol}"
	python3 tools/extract-dtb/extract-dtb.py working/bootdevice.img -o working/bootdtb > /dev/null 2>&1
	# Extract dts
	mkdir dumps/$DEVICE/bootdts
	dtb_list=`find working/bootdtb -name '*.dtb' -type f -printf '%P\n' | sort`
	for dtb_file in $dtb_list; do
		echo -e "${bold}${cyan}Extracting dts from $dtb_file${nocol}"
		dtc -I dtb -O dts -o dumps/$DEVICE/bootdts/$dtb_file working/bootdtb/$dtb_file > /dev/null 2>&1
		mv dumps/$DEVICE/bootdts/$dtb_file $(echo "dumps/$DEVICE/bootdts/$dtb_file" | sed -r 's|.dtb|.dts|g')
	done
fi

# Copy to dumps
for imgdir in "${arr[@]}"; do
	if [ -e working/$imgdir.img ]; then
		echo -e "${bold}${cyan}Copying ${imgdir} to dumps/${DEVICE}/${nocol}"
		cp -a working/$imgdir/ dumps/$DEVICE/ > /dev/null 2>&1
	fi
done

# Store baseband, trustzone & vendor version in board-info.txt
if [ -e working/modem.img ]; then
	strings working/modem.img | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> dumps/$DEVICE/board-info.txt
fi
find working/ -type f \( -name "tz.mbn" -o -name "tz.img" -o -name "tz_*" \) -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> dumps/$DEVICE/board-info.txt
if [ -e dumps/$DEVICE/vendor/build.prop ]; then
	strings dumps/$DEVICE/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> dumps/$DEVICE/board-info.txt
fi
echo -e "${bold}${cyan}$(cat dumps/${DEVICE}/board-info.txt)${nocol}"

# List ROM
find dumps/$DEVICE/ -type f -printf '%P\n' | sort | grep -v ".git/" > dumps/$DEVICE/all_files.txt

# Cleanup
clean_up

if [ $? -eq 0 ]; then
	# Display time taken
	duration=$SECONDS
	echo -e "${bold}${cyan}Extract time: $(($duration / 60)) minutes and $(($duration % 60)) seconds.${nocol}"
else
	echo -e "${bold}${red}Extract failed.${nocol}"
fi

# Create repo
if [ "$create_repo" == "y" ]; then
	. "$PROJECT_DIR"/tools/dump_push.sh "$PROJECT_DIR"/dumps/"$DEVICE"
fi
}

# Extract ROM zip to working
if [ -z "$(ls -A $PROJECT_DIR/input/* | grep -v "place_rom_zip_here.txt")" ]; then
	echo -e "${bold}${red}No zip or gz file detected in input folder.${nocol}"
	exit
else
	find $PROJECT_DIR/input/ -type f,l -name "*.ozip" -exec python3 $PROJECT_DIR/tools/oppo_ozip_decrypt/ozipdecrypt.py {} \;
	rm -rf $PROJECT_DIR/input/*.ozip
	rom_list=`find $PROJECT_DIR/input/ -type f,l -printf '%P\n' | sort | grep -v "place_rom_zip_here.txt"`
	for file in $rom_list; do
		ZIP_FORMAT=`echo $file | sed 's|.*\.||'`
		echo -e "${bold}${cyan}Extracting $file${nocol}"
		if [ "$ZIP_FORMAT" == "zip" ]; then
			unzip $PROJECT_DIR/input/${file} -d $PROJECT_DIR/working
		elif [ "$ZIP_FORMAT" == "gz" ] || [ "$ZIP_FORMAT" == "tgz" ]; then
			tar -zxvf $PROJECT_DIR/input/${file} -C $PROJECT_DIR/working
			for i in "${arr[@]}" "boot"; do
				find working/ -name "$i.img" -exec mv {} $PROJECT_DIR/working/$i.img \;
			done
		fi
		if ! [ $(find $PROJECT_DIR/working/ -name 'META-INF' | wc -l) -gt 0 ]; then
			IS_FASTBOOT=y
		else
			IS_FASTBOOT=n
		fi
		core
	done
fi
