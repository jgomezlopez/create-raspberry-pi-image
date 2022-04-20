#!/bin/bash

MOUNTPOINT=raspian
MOUNTPOINT_BOOT=raspianboot
if [[ $# -ne 3 ]]; then
    echo "Illegal number of parameters" >&2
    exit 3
fi

IMAGE=`echo $1 | sed "s/\.bz2$//g" | sed "s/\.img$//g"`
PIPELINE=$2
CONFIG=$3
	NEWIMAGE=${IMAGE}-${PIPELINE}.img
	if [ ! -f ${NEWIMAGE}.bz2 ]; then
		echo "Creating ${NEWIMAGE}"
		# Decompress base image
		if [ -f ${IMAGE}.img.bz2 ]; then
			bzcat ${IMAGE}.img.bz2 > ${NEWIMAGE}
		else
			if [ -f ${IMAGE}.img ]; then
				cp ${IMAGE}.img ${NEWIMAGE}
			else
				echo "Image not found"
				exit 1
			fi
		fi

		# Mount the images
		if [ ! -d ${MOUNTPOINT} ]; then
			sudo mkdir ${MOUNTPOINT}
		fi
		if [ ! -d ${MOUNTPOINT_BOOT} ]; then
			sudo mkdir ${MOUNTPOINT_BOOT}
		fi
		
		dd if=/dev/zero bs=1M count=1024 >> ${NEWIMAGE} 
		NEWSIZE=`fdisk -lu ${NEWIMAGE} | tail -2 | head -1 | awk '{print $3*512/(1024*1024)+1024}'` 
		losetup -f -P --show ${NEWIMAGE}

		parted -s /dev/loop0 resizepart 2 ${NEWSIZE}MB
		e2fsck -f /dev/loop0p2
		resize2fs /dev/loop0p2
		e2fsck -f /dev/loop0p2

		mount /dev/loop0p2 -o rw ${MOUNTPOINT}
		mount /dev/loop0p1 -o rw ${MOUNTPOINT_BOOT}

		# mount binds
		mount --bind /dev ${MOUNTPOINT}/dev/
		mount --bind /sys ${MOUNTPOINT}/sys/
		mount --bind /proc ${MOUNTPOINT}/proc/
		mount --bind /dev/pts ${MOUNTPOINT}/dev/pts

		# Modify image for mounting with QEMU
		## Preload libraries
		sudo mv ${MOUNTPOINT}/etc/ld.so.preload ${MOUNTPOINT}/etc/ld.so.preload.orig 
		cat ${MOUNTPOINT}/etc/ld.so.preload.orig | sed "s/^/#/g" > ld.so.preload.tmp
		sudo mv ld.so.preload.tmp ${MOUNTPOINT}/etc/ld.so.preload 
		## copy configuration files
		mkdir ${MOUNTPOINT}/home/pi/conf
		mount --bind {$CONFIG}/conf ${MOUNTPOINT}/home/pi/conf

		cp {$CONFIG}/conf/wpa_supplicant.conf ${MOUNTPOINT_BOOT}/wpa_supplicant.conf
		cp {$CONFIG}/chroot.sh ${MOUNTPOINT}/chroot.sh
		cat ${MOUNTPOINT_BOOT}/config.txt | sed "s/dtoverlay=.*$/dtoverlay=vc4-fkms-v3d/g" > ${MOUNTPOINT_BOOT}/config.txt ${MOUNTPOINT_BOOT}/config.txt.new 
		cp ${MOUNTPOINT_BOOT}/config.txt.new ${MOUNTPOINT_BOOT}/config.txt 
		rm ${MOUNTPOINT_BOOT}/config.txt.new
		
		# copy qemu binary
		cp /usr/bin/qemu-arm-static ${MOUNTPOINT}/usr/bin/

		chmod a+x ${MOUNTPOINT}/chroot.sh

		# chroot to raspbian
		chroot ${MOUNTPOINT} /chroot.sh

		# revert ld.so.preload fix
		sed -i 's/^#//g' ${MOUNTPOINT}/etc/ld.so.preload

		# remove qemu binary
		rm ${MOUNTPOINT}/usr/bin/qemu-arm-static 

		# remove chroot script
		rm ${MOUNTPOINT}/chroot.sh 

		## umount image
		umount ${MOUNTPOINT}/home/pi/conf
		rm -rf ${MOUNTPOINT}/home/pi/conf
		umount ${MOUNTPOINT}/{dev/pts,dev,sys,proc,}
		umount ${MOUNTPOINT_BOOT}
		e2fsck -f /dev/loop0p2
		losetup -d /dev/loop0
		echo "Compresing $NEWIMAGE"
		bzip2 -9 ${NEWIMAGE}
	else
		echo "The target image exists"
		exit 2
	fi
