#!/sbin/sh

# if you want to modify this tool for your own device, usually it should be enough to change these two variables
FSTAB="fstab.grouper"
BOOT_PARTITION="/dev/block/platform/sdhci-tegra.3/by-name/LNX"

# get file descriptor for output (CWM)
OUTFD=$(ps | grep -v "grep" | grep -o -E "update_binary(.*)" | cut -d " " -f 3);

# get file descriptor for output (TWRP)
[ $OUTFD != "" ] || OUTFD=$(ps | grep -v "grep" | grep -o -E "updater(.*)" | cut -d " " -f 3)

# functions to send output to recovery
progress() {
	if [ $OUTFD != "" ]; then
		echo "progress ${1} ${2} " 1>&$OUTFD;
	fi;
}

set_progress() {
	if [ $OUTFD != "" ]; then
		echo "set_progress ${1} " 1>&$OUTFD;
	fi;
}

ui_print() {
	if [ $OUTFD != "" ]; then
		echo "ui_print ${1} " 1>&$OUTFD;
		echo "ui_print " 1>&$OUTFD;
	else
		echo "${1}";
	fi;
}

restore() {
	# UNDOING UGLY HACK
	# EDIT: solved by using Android Image Kitchen 1.6, hopefully.
	#
	# cd /system
	# rm -f bin
	# mv bin.bak bin

	# mount the partitions back
	if [ $DATA_MOUNTED -eq 0 ]; then
		mount /data 2> /dev/null
	else
		umount /data 2> /dev/null
	fi

	if [ $CACHE_MOUNTED -eq 0 ]; then
		mount /cache 2> /dev/null
	else
		umount /cache 2> /dev/null
	fi

	if [ $SYSTEM_MOUNTED -eq 0 ]; then
		mount /system 2> /dev/null
	else
		umount /system 2> /dev/null
	fi
}

# check which partitions were mounted so we can restore them later
mount | grep -q '/data'
DATA_MOUNTED=$?
mount | grep -q '/cache'
CACHE_MOUNTED=$?
mount | grep -q '/system'
SYSTEM_MOUNTED=$?

# make sure all the needed partitions are mounted so they show up in mount
# this may output errors if the partition is already mounted (/data and /cache probably will be), so pipe them to /dev/null
# make sure we mount /system before calling any additional shell scripts,
# because they may use /system/bin/sh instead of /sbin/sh and that may cause problems
mount /system 2> /dev/null
mount /cache 2> /dev/null
mount /data 2> /dev/null

# find out which partitions are formatted as F2FS
mount | grep -q 'system type f2fs'
SYSTEM_F2FS=$?
mount | grep -q 'cache type f2fs'
CACHE_F2FS=$?
mount | grep -q 'data type f2fs'
DATA_F2FS=$?

# UGLY HACK
# unmount /system and create fake /system/bin link to /sbin
# there is a problem with Android Image Kitchen binaries because they use /system/bin/linker
# when that is not available they fail
# EDIT: solved by using Android Image Kitchen 1.6, hopefully.
# If only I had tried that before spending a better part of the day searching for the cause of the errors.
#
# umount /system 2> /dev/null
# cd /system
# mv bin bin.bak
# ln -s /sbin bin

# unpack the boot.img and subsequently ramdisk via Android Image Kitchen by osm0sis (http://github.com/osm0sis)
cd /tmp/agnostic-kernel/tools/AIK-mobile/
./unpackimg.sh /tmp/agnostic-kernel/boot.img
UNPACK_SUCCESSFUL=$?

if [ $UNPACK_SUCCESSFUL -eq 0 ]; then
	ui_print "Boot.img unpacked."
	set_progress 0.4
else
	ui_print "Error unpacking boot.img."
	ui_print "No changes were done to the device."
	ui_print "Please contact the kernel developer to resolve the error."
	restore
	return 1
fi

# delete the right lines from the fstab and copy it to ramdisk
ui_print "Setting the right partition layout..."

if [ $SYSTEM_F2FS -eq 0 ]; then
	sed -i "/system.*ext4/d" /tmp/agnostic-kernel/fstab/$FSTAB
else
	sed -i "/system.*f2fs/d" /tmp/agnostic-kernel/fstab/$FSTAB
fi

if [ $CACHE_F2FS -eq 0 ]; then
	sed -i "/cache.*ext4/d" /tmp/agnostic-kernel/fstab/$FSTAB
else
	sed -i "/cache.*f2fs/d" /tmp/agnostic-kernel/fstab/$FSTAB
fi

if [ $DATA_F2FS -eq 0 ]; then
	sed -i "/data.*ext4/d" /tmp/agnostic-kernel/fstab/$FSTAB
else
	sed -i "/data.*f2fs/d" /tmp/agnostic-kernel/fstab/$FSTAB
fi

cp -f /tmp/agnostic-kernel/fstab/$FSTAB /tmp/agnostic-kernel/tools/AIK-mobile/ramdisk/$FSTAB
set_progress 0.5

# repack the ramdisk and subsequently boot.img via Android Image Kitchen by osm0sis (http://github.com/osm0sis)
# no parameters are needed because they got saved by the unpacking
./repackimg.sh
REPACK_SUCCESSFUL=$?

if [ $REPACK_SUCCESSFUL -eq 0 ]; then
	ui_print "Boot.img repacked."
	set_progress 0.7
else
	ui_print "Error repacking boot.img."
	ui_print "No changes were done to the device."
	ui_print "Please contact the kernel developer to resolve the error."
	restore
	return 1
fi

# flash the repacked boot.img to the right partition
# this is the only line doing actual permanent changes to the device
# not sure why flash-image doesn't work here, I always get error -1... so I have to dd it, not cool
# if anyone knows, please tell me :-)
dd if=/tmp/agnostic-kernel/tools/AIK-mobile/image-new.img of=$BOOT_PARTITION
DD_SUCCESSFUL=$?

if [ $DD_SUCCESSFUL -eq 0 ]; then
	ui_print "Boot.img succesfully flashed."
	set_progress 0.8
else
	ui_print "Error flashing boot.img."
	ui_print "Please flash a working kernel before rebooting."
	ui_print "Please contact the kernel developer to resolve the error."
	restore
	return 1
fi

ui_print "Restoring mounts..."
restore

set_progress 0.9
return 0;

