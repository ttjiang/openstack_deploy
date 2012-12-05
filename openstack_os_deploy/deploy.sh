#!/bin/bash

DIR="/opt/openstack"

##check cobbler puppet has been installed##

sudo rpm -qa | grep cobbler
if [ $? -ne 0 ];then
    echo "Please install cobbler.......,run install.sh"
    exit 1
fi

#sudo rpm -qa | grep puppet
#if [ $? -ne 0 ];then
#    echo "Please install puppet.......,run install.sh"
#    exit 1
#fi

#sudo rpm -qa | grep facter
#if [ $? -ne 0 ];then
#    echo "Please install facter.......,run install.sh"
#    exit 1
#fi

##check end##


##read host configuration##

if [ ! -f $DIR/host.template ];then
    echo "host.template does not exist,so exit"
    exit
fi

while read line
do
    if [ "$line" == "" ];then
        continue
    fi
    if [ "${line:0:1}" == "#" ];then
        continue
    fi
    ip_addr=`echo $line|awk '{print $1}'`
    mac_addr=`echo $line|awk '{print $2}'`
    hostname=`echo $line|awk '{print $3}'`
    if [ "$mac_addr" == "" ] || [ "$ip_addr" == "" ] || [ "$hostname" == "" ];then
        echo "you must fill in host.template in right format, now exit"
        exit
    fi
done  < ./host.template


########################################################################
#start cobbler 
########################################################################
echo 
echo "##############################################################"
echo "check ftp"
echo "##############################################################"

rpm -qa | grep vsftpd >/dev/null 2>&1

if [ $? -eq 0 ]
then
    echo 
    echo "ftp server has been install successfully, continue"
    echo
else
    echo
    echo "ftp server has not been installed"
    echo 
    exit
fi

sed -i "s/^Listen.*/Listen 7112/g" /etc/httpd/conf/httpd.conf
sed -i "s/http_port:.*/http_port: 7112/g" /etc/cobbler/settings


service iptables stop >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1

echo "##############################################################"
echo "Begin to configue cobbler"
echo "##############################################################"


service vsftpd restart

if [ $? -ne 0 ];then
        echo
        echo "ftp start error"
        echo 
        exit
fi

service httpd restart

if [ $? -ne 0 ];then
        echo
        echo "httpd start error"
        echo 
        exit
fi

service cobblerd restart

if [ $? -ne 0 ];then
        echo
        echo "cobblerd start error"
        echo 
        exit
fi

echo 
echo "------------------------------------"
echo "2 configue /etc/cobbler/setings"
echo

cobbler_server_ip=`sed -n '/cobbler_server_ip/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
subnet=`sed -n '/subnet_ip/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
subnet_netmask=`sed -n '/subnet_netmask/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
range_ip_start=`sed -n '/range_ip_start/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
range_ip_stop=`sed -n '/range_ip_stop/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
gateway=`sed -n '/gateway_ip/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
netmask=`sed -n '/netmask_ip/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`
dns=`sed -n '/dns_ip/p' "$DIR"/openstack_deploy.conf | awk '{print $2}'`

sed -i "s/next_server:.*/next_server: $cobbler_server_ip/g" /etc/cobbler/settings
sed -i "s/server:.*/server: $cobbler_server_ip/g" /etc/cobbler/settings
sed -i "s/manage_dhcp:.*/manage_dhcp: 1/g" /etc/cobbler/settings
sed -i "s/pxe_just_once:.*/pxe_just_once: 1/g" /etc/cobbler/settings


sed -i "s/disablei.*/disable  = no /g" /etc/xinetd.d/tftp

sed -i "s/disable.*/disable  = no /g" /etc/xinetd.d/rsync

echo "-------------------------------------------------"
echo "4 configure dhcp.template"
echo

rm -rf /etc/cobbler/dhcp.template
cp dhcp.template /etc/cobbler/dhcp.template
sed -i "s/subnet.*netmask.*{/subnet $subnet netmask $subnet_netmask {/g" /etc/cobbler/dhcp.template
sed -i "s/option routers.*/option routers    $gateway;/g" /etc/cobbler/dhcp.template
sed -i "s/option domain-name-servers.*/option domain-name-servers    $dns;/g" /etc/cobbler/dhcp.template
sed -i "s/option subnet-mask.*/option subnet-mask    $netmask;/g" /etc/cobbler/dhcp.template
sed -i "s/range dynamic-bootp.*/range dynamic-bootp    $range_ip_start $range_ip_stop;/g" /etc/cobbler/dhcp.template

cobbler sync >> cobbler.log 2>&1


mount | grep "/mnt"
if [ $? -ne 0 ];then
    echo
    echo "please mount your ISO or CD to /mnt"
    echo 
    exit
fi


echo
echo "---------------------------------------"
echo "5 create distro"
echo
cobbler distro remove --name=openstack_rhel-x86_64 >/dev/null 2>&1
rm -rf  /var/www/cobbler/ks_mirror/openstack_rhel-x86_64/ >/dev/null 2>&1
cobbler import --path=/mnt --name=openstack_rhel --arch=x86_64 >> cobbler_openstack.log 2>&1

if [ $? -ne 0 ];then
    echo
    echo "create distro error"
    echo 
    exit
fi

ks="ks.cfg"

\cp -rf $DIR/$ks /var/www/

sed -i "s/ftp:\/\/192\.168\.1\.1\/pub/http:\/\/$cobbler_server_ip:7112\/cobbler\/ks_mirror\/openstack_rhel-x86_64/g" /var/www/$ks


echo
echo "---------------------------------------"
echo "6 create profile"
echo

cobbler profile edit --name=openstack_rhel-x86_64 --distro=openstack_rhel-x86_64 --kickstart=/var/www/$ks >> cobbler_openstack.log 2>&1


if [ $? -ne 0 ];then
    echo
    echo "create profile error"
    echo 
    exit
fi

echo
echo "---------------------------------------"
echo "7 create system"

if [ ! -f $DIR/host.template ];then
    echo "host.template does not exist,so exit"
    exit
fi

while read line
do
    if [ "$line" == "" ];then
        continue
    fi
    if [ "${line:0:1}" == "#" ];then
        continue
    fi
    ip_addr=`echo $line|awk '{print $1}'`
    mac_addr=`echo $line|awk '{print $2}'`
    hostname=`echo $line|awk '{print $3}'`
    if [ "$mac_addr" == "" ] || [ "$ip_addr" == "" ] || [ "$hostname" == "" ];then
        echo "you must fill in host.template in right format, now exit"
        exit
    fi

    rm -rf /var/www/$mac_addr > /dev/null 2>&1
    mkdir /var/www/$mac_addr
    cp /var/www/$ks /var/www/$mac_addr/ks.cfg
    sed -i "s/DEVICE=.*/DEVICE=eth0/g" /var/www/$mac_addr/ks.cfg
    sed -i "s/IPADDR=.*/IPADDR=$ip_addr/g" /var/www/$mac_addr/ks.cfg
    sed -i "s/NETMASK=.*/NETMASK=$netmask/g" /var/www/$mac_addr/ks.cfg
    sed -i "s/GATEWAY=.*/GATEWAY=$gateway/g" /var/www/$mac_addr/ks.cfg
    sed -i "s/DNS1=.*/DNS1=$dns/g" /var/www/$mac_addr/ks.cfg
    sed -i "s/127\.0\.0\.1/$cobbler_server_ip/g" /var/www/$mac_addr/ks.cfg
    echo "\$SNIPPET('kickstart_done')" >> /var/www/$mac_addr/ks.cfg
    cobbler system remove --name=$mac_addr > /dev/null 2>&1
    cobbler system add --name=$mac_addr --profile=openstack_rhel-x86_64 --mac=$mac_addr --static=yes --ip-address=$ip_addr --kickstart=/var/www/$mac_addr/ks.cfg --hostname=$hostname --netboot-enabled=true

done  < ./host.template


service httpd restart

if [ $? -ne 0 ]
then
        echo
        echo "httpd start error , please check it"
        echo
        exit
fi
service cobblerd restart

if [ $? -ne 0 ]
then
    echo
    echo "cobbler start error , please check it"
fi

service xinetd restart

cobbler sync >> cobbler.log 2>&1
if [ $? -ne 0 ];then
    echo
    echo "cobbler sync error."
    echo 
    exit
fi

