export CROSS_COMPILE=../toolchain/bin/arm-eabi-
export ARCH=arm
export USE_SEC_FIPS_MODE=true
make kali_defconfig
make
make modules SUBDIRS=drivers/net/wireless/bmdhd_mon
cp -rf drivers/net/wireless/bmdhd_mon/dhd.ko