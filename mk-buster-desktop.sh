#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

if [ ! $SOC ]; then
	SOC="rk3568"
fi

install_packages() {
    case $SOC in
        rk3399|rk3399pro)
		MALI=midgard-t86x-r18p0
		ISP=rkisp
		RGA=rga
		;;
        rk3328)
		MALI=utgard-450
		ISP=rkisp
		RGA=rga
		;;
        rk356x|rk3566|rk3568)
		MALI=bifrost-g52-g2p0
		ISP=rkaiq_rk3568
		RGA=rga
		;;
        rk3588|rk3588s)
		ISP=rkaiq_rk3588
		MALI=valhall-g610-g6p0
		RGA=rga2
		;;
    esac
}

case "${ARCH:-$1}" in
	arm|arm32|armhf)
		ARCH=armhf
		;;
	*)
		ARCH=arm64
		;;
esac

echo -e "\033[36m Building for $ARCH \033[0m"

if [ ! $VERSION ]; then
	VERSION="release"
fi

if [ ! -e linaro-buster-desktop-alip-*.tar.gz ]; then
	echo -e "\033[36m Run mk-base-debian.sh first \033[0m"
	exit -1
fi

finish() {
	sudo umount $TARGET_ROOTFS_DIR/dev
	exit -1
}
trap finish ERR

sudo rm -rf binary/

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf linaro-buster-desktop-alip-*.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

#GPU/RGA/CAMERA packages folder
install_packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/libmali/libmali-*$MALI*-x11*.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/camera_engine/camera_engine_$ISP*.deb $TARGET_ROOTFS_DIR/packages/install_packages
sudo cp -rpf packages/$ARCH/$RGA/*.deb $TARGET_ROOTFS_DIR/packages/install_packages

# overlay folder
sudo cp -rf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
	sudo cp -rf overlay-debug/* $TARGET_ROOTFS_DIR/
fi

# adb
if [[ "$ARCH" == "armhf" && "$VERSION" == "debug" ]]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd-32 $TARGET_ROOTFS_DIR/usr/bin/adbd
elif [[ "$ARCH" == "arm64" && "$VERSION" == "debug" ]]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd-64 $TARGET_ROOTFS_DIR/usr/bin/adbd
fi

echo -e "\033[36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
	sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi
sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

echo "deb [arch=arm64] https://cloud.embedfire.com/mirrors/ebf-debian buster main" | sudo tee -a /etc/apt/sources.list
echo "deb [arch=arm64] https://cloud.embedfire.com/mirrors/ebf-debian carp-rk356x main" | sudo tee -a /etc/apt/sources.list

curl https://Embedfire.github.io/keyfile | sudo apt-key add -

apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

export APT_INSTALL="apt-get install -fy --allow-downgrades"

#--------------- lubancat --------------
\${APT_INSTALL} toilet mpv

passwd root <<IEOF
root
root
IEOF

systemctl disable apt-daily.service
systemctl disable apt-daily.timer

systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily-upgrade.service

# set localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# allow root login
sed -i '/pam_securetty.so/s/^/# /g' /etc/pam.d/login

#Desktop
chown -hR cat:cat /home/cat/.config
\${APT_INSTALL} numix-gtk-theme numix-icon-theme-circle
ln -sf /etc/alternatives/lubancat-wallpaper.png /etc/alternatives/desktop-background

#---------------power management --------------
\${APT_INSTALL} pm-utils triggerhappy
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service

#---------------Rga--------------
\${APT_INSTALL} /packages/rga/*.deb

echo -e "\033[36m Setup Video.................... \033[0m"

\${APT_INSTALL} /packages/mpp/*
\${APT_INSTALL} /packages/gst-rkmpp/*.deb
\${APT_INSTALL} /packages/gstreamer/*.deb
\${APT_INSTALL} /packages/gst-plugins-base1.0/*.deb
\${APT_INSTALL} /packages/gst-plugins-bad1.0/*.deb
\${APT_INSTALL} /packages/gst-plugins-good1.0/*.deb
\${APT_INSTALL} /packages/gst-plugins-ugly1.0/*.deb

#---------Camera---------
echo -e "\033[36m Install camera.................... \033[0m"
\${APT_INSTALL} cheese v4l-utils
\${APT_INSTALL} /packages/libv4l/*.deb

#---------Xserver---------
echo -e "\033[36m Install Xserver.................... \033[0m"
\${APT_INSTALL} /packages/xserver/*.deb

#---------------Openbox--------------
echo -e "\033[36m Install openbox.................... \033[0m"
\${APT_INSTALL} /packages/openbox/*.deb

#---------update chromium-----
\${APT_INSTALL} /packages/chromium/*.deb

#------------------libdrm------------
echo -e "\033[36m Install libdrm.................... \033[0m"
\${APT_INSTALL} /packages/libdrm/*.deb

#------------------libdrm-cursor------------
echo -e "\033[36m Install libdrm-cursor.................... \033[0m"
\${APT_INSTALL} /packages/libdrm-cursor/*.deb

# Only preload libdrm-cursor for X
sed -i "/libdrm-cursor.so/d" /etc/ld.so.preload
sed -i "1aexport LD_PRELOAD=libdrm-cursor.so.1" /usr/bin/X

#------------------pcmanfm------------
#echo -e "\033[36m Install pcmanfm.................... \033[0m"
#\${APT_INSTALL} /packages/pcmanfm/*.deb

#------------------blueman------------
echo -e "\033[36m Install blueman.................... \033[0m"
\${APT_INSTALL} blueman
echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
\${APT_INSTALL} blueman
rm -f /usr/sbin/policy-rc.d

#------------------rkwifibt------------
echo -e "\033[36m Install rkwifibt.................... \033[0m"
\${APT_INSTALL} /packages/rkwifibt/*.deb
ln -sf /system/etc/firmware /vendor/etc/

if [ "$VERSION" == "debug" ]; then
#------------------glmark2------------
echo -e "\033[36m Install glmark2.................... \033[0m"
\${APT_INSTALL} /packages/glmark2/*.deb
fi

#------------------rknpu2------------
echo -e "\033[36m Install rknpu2.................... \033[0m"
tar xvf /packages/rknpu2/*.tar -C /

#------------------rktoolkit------------
echo -e "\033[36m Install rktoolkit.................... \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

# cho -e "\033[36m Install Chinese fonts.................... \033[0m"
# # Uncomment zh_CN.UTF-8 for inclusion in generation
# sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' /etc/locale.gen
# echo "LANG=zh_CN.UTF-8" >> /etc/default/locale

# # Generate locale
# locale-gen

# # Export env vars
# echo "export LC_ALL=zh_CN.UTF-8" >> ~/.bashrc
# echo "export LANG=zh_CN.UTF-8" >> ~/.bashrc
# echo "export LANGUAGE=zh_CN.UTF-8" >> ~/.bashrc

# source ~/.bashrc

\${APT_INSTALL} ttf-wqy-zenhei xfonts-intl-chinese

# HACK debian to fix bug
\${APT_INSTALL} fontconfig --reinstall

#------------------pulseaudio---------
echo -e "\033[36m Install pulseaudio................. \033[0m"
cp /etc/pulse/daemon.conf /
cp /etc/pulse/default.pa /
yes|\${APT_INSTALL} /packages/pulseaudio/*.deb
mv /daemon.conf /default.pa /etc/pulse/

apt install -fy --allow-downgrades /packages/install_packages/*.deb

#------remove unused packages------------
apt remove --purge -fy linux-firmware*

# mark package to hold
apt list --installed | grep -v oldstable | cut -d/ -f1 | xargs apt-mark hold

# mark rga package to unhold
apt-mark unhold librga2 librga-dev librga2-dbgsym

#---------------Custom Script--------------
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
rm /lib/systemd/system/wpa_supplicant@.service

#---------------Clean--------------
if [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ;
then
        cd /usr/lib/arm-linux-gnueabihf/dri/
        cp kms_swrast_dri.so swrast_dri.so /
        rm /usr/lib/arm-linux-gnueabihf/dri/*.so
        mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif [ -e "/usr/lib/aarch64-linux-gnu/dri" ];
then
        cd /usr/lib/aarch64-linux-gnu/dri/
        cp kms_swrast_dri.so swrast_dri.so /
        rm /usr/lib/aarch64-linux-gnu/dri/*.so
        mv /*.so /usr/lib/aarch64-linux-gnu/dri/
        rm /etc/profile.d/qt.sh
fi
cd -

#---------------Clean--------------
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages

EOF

sudo umount $TARGET_ROOTFS_DIR/dev

IMAGE_VERSION=desktop ./mk-image.sh 