#!/bin/bash -e

if [[ "$RELEASE" == "stretch" || "$RELEASE" == "9" ]]; then
	RELEASE='stretch'
elif [[ "$RELEASE" == "buster" || "$RELEASE" == "10" ]]; then
	RELEASE='buster'
else
    echo -e "\033[36m please input the os type,stretch or buster...... \033[0m"
fi

if [ "$ARCH" == "armhf" ]; then
	ARCH='armhf'
elif [ "$ARCH" == "arm64" ]; then
	ARCH='arm64'
else
    echo -e "\033[36m please input the os type,armhf or arm64...... \033[0m"
fi

if [ ! $TARGET ]; then
	TARGET='desktop'
fi

if [ -e linaro-$RELEASE-$TARGET-alip-*.tar.gz ]; then
	rm linaro-$RELEASE-$TARGET-alip-*.tar.gz
fi

sudo rm -rf binary/

cd ubuntu-build-service/$RELEASE-$TARGET-$ARCH

echo -e "\033[36m Staring Download...... \033[0m"

make clean

./configure

make

DATE=$(date +%Y%m%d)
if [ -e linaro-$RELEASE-alip-*.tar.gz ]; then
	sudo chmod 0666 linaro-$RELEASE-alip-*.tar.gz
	mv linaro-$RELEASE-alip-*.tar.gz ../../linaro-$RELEASE-$TARGET-alip-$DATE.tar.gz
else
	echo -e "\e[31m Failed to run livebuild, please check your network connection. \e[0m"
fi
