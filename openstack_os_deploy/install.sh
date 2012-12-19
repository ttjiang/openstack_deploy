#!/bin/bash 

##start create repo###
rm -rf /var/ftp/openstack-repo >/dev/null 2>&1
mkdir /var/ftp/openstack-repo
cp openstack-packages.tar.gz /var/ftp/openstack-repo/
cd /var/ftp/openstack-repo/
tar xvf openstack-packages.tar.gz openstack-packages

rpm -qa | grep createrepo
if [ $? -ne 0 ];then
    rpm -ivh /var/ftp/openstack-repo/openstack-packages/deltarpm-3.5-0.5.20090913git.el6.x86_64.rpm
    rpm -ivh /var/ftp/openstack-repo/openstack-packages/python-deltarpm-3.5-0.5.20090913git.el6.x86_64.rpm
    rpm -ivh /var/ftp/openstack-repo/openstack-packages/createrepo-0.9.8-4.el6.noarch.rpm
fi

createrepo /var/ftp/openstack-repo/openstack-packages

####

service vsftpd restart
chkconfig vsftpd on

touch /etc/yum.repos.d/openstack.repo

echo "[openstack]" > /etc/yum.repos.d/openstack.repo

echo "name=openstack" >> /etc/yum.repos.d/openstack.repo

echo "baseurl=ftp://127.0.0.1/openstack-repo/openstack-packages" >> /etc/yum.repos.d/openstack.repo

echo "enabled=1" >> /etc/yum.repos.d/openstack.repo

echo "gpgcheck=0" >> /etc/yum.repos.d/openstack.repo

yum install dhcp tftp-server syslinux cobbler puppet-server -y




