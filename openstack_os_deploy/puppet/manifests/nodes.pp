class deploy{
        file{ "/opt/openstack/stack.sh":
                ensure => present,
                alias => "stack.sh",
                source => "puppet:///files/stack.sh",
                owner => root,
                group => root,
                mode => 755;
        }

        file{ "/opt/openstack/nova.conf":
                ensure => present,
                alias => "nova.conf",
                source => "puppet:///files/nova.conf",
                owner => root,
                group => root,
                mode => 640;
        }

        file{ "/opt/openstack/keystone-init.py":
                ensure => present,
                alias => "keystone-init.py",
                source => "puppet:///files/keystone-init.py",
                owner => root,
                group => root,
                mode => 755;
        }

        file{ "/opt/openstack/config.yaml":
                ensure => present,
                alias => "config.yaml",
                source => "puppet:///files/config.yaml",
                owner => root,
                group => root,
                mode => 644;
        }

        exec{ "ospc":
                command => "/bin/bash /opt/openstack/stack.sh",
                require => File["/opt/openstack/stack.sh","/opt/openstack/nova.conf","/opt/openstack/keystone-init.py","/opt/openstack/config.yaml"],
                path => ["/bin", "/usr/bin","/sbin","/usr/sbin"],
        }

        exec{ "rm":
                command => "sed -i '/start.sh/d' /etc/rc.local",
                path => ["/bin", "/usr/bin"],
        }
}

