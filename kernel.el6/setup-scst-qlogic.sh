#!/bin/bash
#######################################

DO()
{
 eval "$1 2>> $BUILD_LOG | tee -a $BUILD_LOG"
}

# FUNCTION : Echoes a command into an install log
LOG()
{
 echo "$1" >> $BUILD_LOG
}

# FUNCTION : Print message and quit
SEE_LOG()
{
 DO 'echo && echo "Check the log file $INST_LOG for detailed diagnostic messages or installation success/failures..."'

}

BUILD_DIRECTORY=/usr/local/SCST_BUILD/appliance_drivers
BUILD_LOG="build-scst-qlogic.log"
mkdir -p $BUILD_DIRECTORY



# Download scst patch - prerequisite where this script is placed
if [ ! -f scst_72.patch ]; then
	DO 'echo "scst_72.patch patch file is not available. Please download in $PWD directory"	'
	DO 'echo "and execute $PWD/$0 again"'
fi

echo "Following commands will download the source files licensed under GPL v2"
echo "Please press (Y/y) if you accept the terms mentioned at http://sourceforge.net/projects/scst/"
read input

if [ "$input" != "y" ] && [ "$input" != "Y" ]; then
    echo "Please accept the terms to procede further by re-running the script"
    echo 
    exit 1
fi

# Copy scst patch to predefined directory
DO 'echo "Applying "'
cp scst_72.patch $BUILD_DIRECTORY

# Download the scst_72.patch in this directory 
wget http://sourceforge.net/projects/scst/files/iscsi-scst/2.1.0/iscsi-scst-2.1.0.tar.gz
wget http://sourceforge.net/projects/scst/files/qla2x00-target/2.1.0/qla2x00t-2.1.0.tar.gz
wget http://sourceforge.net/projects/scst/files/scst/2.1.0/scst-2.1.0.tar.gz
wget http://sourceforge.net/projects/scst/files/scstadmin/2.1.0/scstadmin-2.1.0.tar.gz
cp *.tar.gz $BUILD_DIRECTORY/
cd $BUILD_DIRECTORY
tar -xvzf scst-2.1.0.tar.gz
tar -xvzf qla2x00t-2.1.0.tar.gz
tar -xvzf iscsi-scst-2.1.0.tar.gz
tar -xvzf scstadmin-2.1.0.tar.gz

mv scst-2.1.0 scst
mv qla2x00t-2.1.0 qla2x00t
mv iscsi-scst-2.1.0 iscsi-scst
mv scstadmin-2.1.0 scstadmin

mkdir scst_rhel6
mv scst qla2x00t iscsi-scst scstadmin scst_rhel6/
cd scst_rhel6
patch -p1 < ../scst_72.patch
cd qla2x00t
gmake
cd ..
gmake all
find . | grep ko$ | grep -v unsigned
cd scstadmin
gmake all
cd ..


# Copy listed drivers to respective path below
scst_ko=`find . -name scst.ko`
scst_vdisk_ko=`find . -name scst_vdisk.ko`
qla2x00tgt_ko=`find . -name qla2x00tgt.ko`
qla2xxx_ko=`find . -name qla2xxx.ko`
iscsi_scst_ko=`find . -name iscsi-scst.ko`

Kernel=`uname -r`
mkdir -p /lib/modules/${Kernel}/extra/dev_handlers
cp $scst_ko /lib/modules/${Kernel}/extra/scst.ko
cp $scst_vdisk_ko /lib/modules/${Kernel}/extra/dev_handlers/scst_vdisk.ko
cp $qla2x00tgt_ko /lib/modules/${Kernel}/extra/qla2x00tgt.ko
cp $qla2xxx_ko /lib/modules/${Kernel}/extra/qla2xxx.ko
cp $iscsi_scst_ko /lib/modules/${Kernel}/extra/iscsi-scst.ko
cd /lib/modules/${Kernel}/extra/
depmod -ae
depmod ${Kernel}
modprobe qla2xxx >/dev/null 2>&1
modprobe scst >/dev/null 2>&1
modprobe scst_vdisk  >/dev/null 2>&1
modprobe qla2x00tgt >/dev/null 2>&1
modprobe iscsi-scst >/dev/null 2>&1

mv /lib/modules/${Kernel}/kernel/drivers/scsi/qla2xxx/qla2xxx.ko /lib/modules/${Kernel}/kernel/drivers/scsi/qla2xxx/qla2xxx.ko.orig

cd $BUILD_DIRECTORY/scst_rhel6
mkinitrd -f /boot/initramfs-${Kernel}.PreAppliance.img ${Kernel}

cp /boot/grub/grub.conf /boot/grub/grub.conf.orig
# Script changes to replace /boot/initramfs-2.6.32-358.23.2.el6.x86_64.img with /boot/initramfs-${Kernel}.PreAppliance.img
# provided 2.6.32-358.23.2.el6.x86_64 is the active kernel

# Removing the empty lines first in the grub.conf file
sed -i -e "/^$/d" /boot/grub/grub.conf
sed -n '
/(2.6.32-358.23.2.el6.x86_64)/ {
h
n
H
n
H
n
H
x
p
}' /boot/grub/grub.conf | sed -e "s/#//" -e "s/(2.6.32-358.23.2.el6.x86_64)/(2.6.32-358.23.2.el6.x86_64.PreAppliance)/" -e "s/initramfs[-][0-9a-zA-Z_.-]*/initramfs-2.6.32-358.23.2.el6.x86_64.PreAppliance.img/" > /boot/grub/contents
sed -n "0,/hiddenmenu/ p" /boot/grub/grub.conf > /boot/grub/grub.conf.new
cat /boot/grub/contents >> /boot/grub/grub.conf.new
sed -n "/hiddenmenu/,$ p" /boot/grub/grub.conf | grep -v hiddenmenu >> /boot/grub/grub.conf.new
mv /boot/grub/grub.conf.new /boot/grub/grub.conf

# User space process/configuration changes SCST
mkdir -p /usr/local/sbin/ /usr/local/share/perl5/SCST/ >/dev/null 2>&1
cp iscsi-scst/usr/iscsi-scstd /usr/local/sbin/iscsi-scstd
cp iscsi-scst/usr/iscsi-scst-adm /usr/local/sbin/iscsi-scst-adm
cp iscsi-scst/etc/scst.conf /etc/scst.conf
cp iscsi-scst/etc/initd/initd.redhat /etc/init.d/iscsi-scst
cp iscsi-scst/etc/obsolete/iscsi-scstd.conf /etc/iscsi-scstd.conf
cp scstadmin/scstadmin.procfs/scst-0.8.22/lib/SCST/SCST.pm /usr/local/share/perl5/SCST/SCST.pm
cp scstadmin/scstadmin.procfs/scstadmin /usr/local/sbin/scstadmin
chmod 755 /usr/local/sbin/iscsi-scstd /usr/local/sbin/iscsi-scst-adm /usr/local/sbin/scstadmin /etc/init.d/iscsi-scst /usr/local/share/perl5/SCST/SCST.pm >/dev/null 2>&1
/sbin/chkconfig iscsi-scst on >/dev/null 2>&1

echo "SCST build and driver install is complete"
echo "SCST build directory is $BUILD_DIRECTORY"
echo "System requires a reboot."

