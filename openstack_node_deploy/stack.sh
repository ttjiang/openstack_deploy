#!/usr/bin/env bash
echo "############################################################"
echo "start install and configure openstack"
echo "############################################################"

DEPLOY_DIR="/opt/openstack"

NODE_TYPE=`sed -n '/NODE_TYPE/p' local.conf | awk '{print $2}'`
ROOT_MYSQL_PASSWORD=`sed -n '/ROOT_MYSQL_PASSWORD/p' local.conf | awk '{print $2}'`
LOG_FILE="$DEPLOY_DIR/stack.log"


###GET NETWORK CONFIGURATION####################
SERVER_YUM_IP=`sed -n '/SERVER_YUM_IP/p' local.conf | awk '{print $2}'`
MY_HOST_IP=`sed -n '/MY_HOST_IP/p' local.conf | awk '{print $2}'`
CC_HOST_IP=`sed -n '/CC_HOST_IP/p' local.conf | awk '{print $2}'`
NETWORK_MANAGER="nova.network.manager.FlatDHCPManager"
PUBLIC_INTERFACE=`sed -n '/PUBLIC_INTERFACE/p' local.conf | awk '{print $2}'`
FLAT_INTERFACE=`sed -n '/FLAT_INTERFACE/p' local.conf | awk '{print $2}'`
FLAT_NETWORK_BRIDGE=`sed -n '/FLAT_NETWORK_BRIDGE/p' local.conf | awk '{print $2}'`
FIXED_RANGE=`sed -n '/FIXED_RANGE/p' local.conf | awk '{print $2}'`
LIBVIRT_TYPE=`sed -n '/LIBVIRT_TYPE/p' local.conf | awk '{print $2}'`

log_write()
{
    echo >> "$1" $LOG_FILE
}

create_yum_rep()
{
    log_write "start create yum repo for openstack install"
    touch /etc/yum.repos.d/openstack.repo
    echo "[openstack]" > /etc/yum.repos.d/openstack.repo
    echo "name=openstack" >> /etc/yum.repos.d/openstack.repo
    echo "baseurl=ftp://$1/openstack-repo/openstack-packages" >> /etc/yum.repos.d/openstack.repo
    echo "enabled=1" >> /etc/yum.repos.d/openstack.repo
    echo "gpgcheck=0" >> /etc/yum.repos.d/openstack.repo
}

create_yum_rep $SERVER_YUM_IP

if [ "$NODE_TYPE" == "cc" ];then

    echo "install ntp"
    sudo yum install -y ntp
    sudo service ntpd start
    sudo chkconfig ntpd on

    echo
    echo "---------------------------------"
    echo "start install and configure keystone"
    echo "---------------------------------"
    echo 
    
    sudo yum install openstack-utils openstack-keystone -y

    sudo yum install mysql mysql-server MySQL-python -y

    sudo chkconfig --level 2345 mysqld on

    sudo service mysqld start

    sudo mysqladmin -u root password "$ROOT_MYSQL_PASSWORD"

    sudo mysql -uroot -p$ROOT_MYSQL_PASSWORD <<EOF
        CREATE DATABASE keystone;
        GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone';
EOF

    ADMIN_TOKEN=$(openssl rand -hex 10)

    sudo openstack-config --set /etc/keystone/keystone.conf DEFAULT admin_token $ADMIN_TOKEN

    sudo sed -i "s/@localhost/@$MY_HOST_IP/g" /etc/keystone/keystone.conf

    sudo service openstack-keystone start && sudo chkconfig openstack-keystone on

    sudo keystone-manage db_sync

    sudo yum install PyYAML -y

    cd $DEPLOY_DIR/keystone-init

    sudo sed -i.bak "s/192.168.206.130/$MY_HOST_IP/g" config.yaml

    sudo sed -i.bak "s/token:.*/token:    $ADMIN_TOKEN/g" config.yaml

    sudo python keystone-init.py config.yaml

    echo "--------keystone end-------------"
    echo

    echo
    echo "---------------------------------"
    echo "start install and configure glance"
    echo "---------------------------------"
    echo

    ADMIN_TENANT_NAME="service"
    ADMIN_USER_GLANCE="glance"
    ADMIN_PASSWORD_GLANCE="glance"

    sudo yum install openstack-glance -y
    
    sudo mysql -uroot -p$ROOT_MYSQL_PASSWORD <<EOF
        CREATE DATABASE glance;
        GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance';
EOF
    sudo openstack-config --set /etc/glance/glance-api.conf paste_deploy flavor keystone
    sudo openstack-config --set /etc/glance/glance-api-paste.ini filter:authtoken admin_token $ADMIN_TOKEN
    sudo openstack-config --set /etc/glance/glance-registry.conf paste_deploy flavor keystone
    sudo openstack-config --set /etc/glance/glance-registry-paste.ini filter:authtoken admin_token $ADMIN_TOKEN

    sudo sed -i "s/admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/g" /etc/glance/glance-api-paste.ini
    sudo sed -i "s/admin_user.*/admin_user = $ADMIN_USER_GLANCE/g" /etc/glance/glance-api-paste.ini
    sudo sed -i "s/admin_password.*/admin_password = $ADMIN_PASSWORD_GLANCE/g" /etc/glance/glance-api-paste.ini

    sudo sed -i "s/admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/g" /etc/glance/glance-registry-paste.ini
    sudo sed -i "s/admin_user.*/admin_user = $ADMIN_USER_GLANCE/g" /etc/glance/glance-registry-paste.ini
    sudo sed -i "s/admin_password.*/admin_password = $ADMIN_PASSWORD_GLANCE/g" /etc/glance/glance-registry-paste.ini

    sudo sed -i "s/pipeline = context registryapp.*/pipeline = authtoken auth-context context registryapp/g" /etc/glance/glance-registry-paste.ini

    sudo sed -i "s/@localhost/@$CC_HOST_IP/g" /etc/glance/glance-registry.conf

    sudo glance-manage db_sync
    sudo service openstack-glance-registry start
    sudo service openstack-glance-registry status
#    if [ $? -ne 0 ];then
    sudo glance-registry --config-file /etc/glance/glance-registry.conf --debug --verbose & 
    echo "sudo glance-registry --config-file /etc/glance/glance-registry.conf --debug --verbose &" >> /etc/rc.local 
#    fi
    sudo service openstack-glance-api start
    sudo chkconfig openstack-glance-registry on
    sudo chkconfig openstack-glance-api on

    echo "--------glance end-----------------"
    echo

fi

echo
echo "---------------------------------"
echo "start install and configure nova"
echo "---------------------------------"
echo

if [ "$NODE_TYPE" == "cc" ];then
    ip link set eth0 promisc on
    touch /etc/sysconfig/network-scripts/ifcfg-br100

    echo "DEVICE=br100" > /etc/sysconfig/network-scripts/ifcfg-br100
    echo "TYPE=Bridge" >> /etc/sysconfig/network-scripts/ifcfg-br100
    echo "ONBOOT=yes" >> /etc/sysconfig/network-scripts/ifcfg-br100
    echo "DELAY=0" >> /etc/sysconfig/network-scripts/ifcfg-br100
    echo "BOOTPROTO=static" >> /etc/sysconfig/network-scripts/ifcfg-br100
    echo "IPADDR=192.168.100.2" >> /etc/sysconfig/network-scripts/ifcfg-br100
    echo "NETMASK=255.255.255.0" >> /etc/sysconfig/network-scripts/ifcfg-br100

    sudo brctl addbr br100
    sudo service network restart

    sudo yum install openstack-nova openstack-nova-novncproxy  memcached qpid-cpp-server -y

    sudo mysql -uroot -p$ROOT_MYSQL_PASSWORD <<EOF
        CREATE DATABASE nova;
        GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY 'nova';
EOF

    #sudo openstack-config --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
    #sudo openstack-config --set /etc/nova/api-paste.ini filter:authtoken admin_token $ADMIN_TOKEN

    ADMIN_USER_NOVA="nova"
    ADMIN_PASSWORD_NOVA="nova"

    sudo sed -i "s/admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/g" /etc/nova/api-paste.ini
    sudo sed -i "s/admin_user.*/admin_user = $ADMIN_USER_NOVA/g" /etc/nova/api-paste.ini
    sudo sed -i "s/admin_password.*/admin_password = $ADMIN_PASSWORD_NOVA/g" /etc/nova/api-paste.ini

    sudo setenforce permissive
    sudo sed -i 's/auth=yes/auth=no/g' /etc/qpidd.conf

    #sudo rm -rf /etc/nova/nova.conf
    #sudo cp $DEPLOY_DIR/nova.conf /etc/nova/nova.conf
    #sudo chown -R root:nova /etc/nova/nova.conf

    sudo sed -i "s/@localhost/@$CC_HOST_IP/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/my_ip =.*/my_ip = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/network_manager =.*/network_manager = $NETWORK_MANAGER/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "/fixed_range =.*/d" $DEPLOY_DIR/nova.conf
    echo "fixed range = $FIXED_RANGE" >> $DEPLOY_DIR/nova.conf

    sudo sed -i "s/flat_interface =.*/flat_interface = $FLAT_INTERFACE/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/flat_network_bridge =.*/flat_network_bridge = $FLAT_NETWORK_BRIDGE/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/libvirt_type =.*/libvirt_type = $LIBVIRT_TYPE/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/novncproxy_base_url =.*/novncproxy_base_url = http:\/\/$CC_HOST_IP:6080\/vnc_auto.html/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/vncserver_proxyclient_address =.*/vncserver_proxyclient_address = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/vncserver_listen =.*/vncserver_listen = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf

    sudo rm -rf /etc/nova/nova.conf
    sudo cp $DEPLOY_DIR/nova.conf /etc/nova/nova.conf
    sudo chown -R root:nova /etc/nova/nova.conf

    if [ $LIBVIRT_TYPE == "qemu" ];then
        sudo ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-system-x86_64
        sudo service libvirtd restart
    fi

    for svc in api objectstore compute network volume scheduler cert novncproxy consoleauth
    do
        sudo service openstack-nova-$svc stop
        sudo chkconfig openstack-nova-$svc on
    done

    sudo nova-manage db sync

    for svc in api objectstore compute network volume scheduler cert novncproxy consoleauth
    do
        sudo service openstack-nova-$svc start
    done
else

    sudo ntpdate $CC_HOST_IP
    sudo hwclock -w
    
    sudo yum install -y openstack-nova-network openstack-nova-compute
    
    ADMIN_USER_NOVA="nova"
    ADMIN_PASSWORD_NOVA="nova"
    
    sudo sed -i "s/admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/g" /etc/nova/api-paste.ini
    sudo sed -i "s/admin_user.*/admin_user = $ADMIN_USER_NOVA/g" /etc/nova/api-paste.ini
    sudo sed -i "s/admin_password.*/admin_password = $ADMIN_PASSWORD_NOVA/g" /etc/nova/api-paste.ini

    sudo setenforce permissive
        
    sudo sed -i "s/@localhost/@$CC_HOST_IP/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/my_ip =.*/my_ip = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/network_manager =.*/network_manager = $NETWORK_MANAGER/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "/fixed_range =.*/d" $DEPLOY_DIR/nova.conf
    echo "fixed range = $FIXED_RANGE" >> $DEPLOY_DIR/nova.conf
    sudo sed -i "s/flat_interface =.*/flat_interface = $FLAT_INTERFACE/g" $DEPLOY_DIR/nova.conf
    sudo sed -i "s/flat_network_bridge =.*/flat_network_bridge = $FLAT_NETWORK_BRIDGE/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/libvirt_type =.*/libvirt_type = $LIBVIRT_TYPE/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/novncproxy_base_url =.*/novncproxy_base_url = http:\/\/$CC_HOST_IP:6080\/vnc_auto.html/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/vncserver_proxyclient_address =.*/vncserver_proxyclient_address = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf

    sudo sed -i "s/vncserver_listen =.*/vncserver_listen = $MY_HOST_IP/g" $DEPLOY_DIR/nova.conf

    sudo rm -rf /etc/nova/nova.conf
    sudo cp $DEPLOY_DIR/nova.conf /etc/nova/nova.conf
    sudo chown -R root:nova /etc/nova/nova.conf

    if [ $LIBVIRT_TYPE == "qemu" ];then
        sudo ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-system-x86_64
        sudo service libvirtd restart
    fi

    sudo service openstack-nova-compute start
    sudo service openstack-nova-network start

    sudo chkconfig openstack-nova-compute on
    sudo chkconfig openstack-nova-network on

fi    

echo 
echo "----------nova end------------------"

if [ "$NODE_TYPE" == "cc" ];then
    echo 
    echo "----------start install dashboard---------"
    echo

    yum install -y openstack-dashboard mod_wsgi

    sudo sed -i "s/CACHE_BACKEND =.*/CACHE_BACKEND = \'memcached:\/\/127.0.0.1:11211\/\'/g" /etc/openstack-dashboard/local_settings

    sudo service memcached start
    sudo chkconfig memcached on

    sudo service httpd start
    sudo chkconfig httpd on

    echo "---------dashboard end---------------------"
fi

