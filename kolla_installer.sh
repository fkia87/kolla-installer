#!/bin/bash

VENV_NAME=fkia_env
IP=192.168.122.94
IF=enp1s0
NEUTRON_IF=enp7s0
DISTRO=ubuntu

sudo apt update && sudo apt upgrade -y

sudo apt -y install python3-dev libffi-dev gcc libssl-dev

sudo apt -y install python3-pip

sudo apt -y install python3.8-venv

python3 -m venv $VENV_NAME

source $VENV_NAME/bin/activate

pip install -U pip

pip install 'ansible<3.0'

pip install git+https://opendev.org/openstack/kolla-ansible@stable/wallaby

sudo mkdir -p /etc/kolla

sudo chown $USER:$(id -gn $USER) /etc/kolla

cp -r /home/$USER/$VENV_NAME/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/

cp /home/$USER/$VENV_NAME/share/kolla-ansible/ansible/inventory/* /etc/kolla/

sudo mkdir /etc/ansible

cat << EOF | sudo tee -a /etc/ansible/ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF

cat << EOF | sudo tee -a /etc/kolla/globals.yml
enable_haproxy: "no"
kolla_internal_vip_address: "$IP"
network_interface: "$IF"
neutron_external_interface: "$NEUTRON_IF"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
kolla_base_distro: "$DISTRO"
EOF

echo -e "\nGenerating password...\n"
kolla-genpwd
echo -e "\nDone!\n"

kolla-ansible -i /etc/kolla/all-in-one bootstrap-servers

kolla-ansible -i /etc/kolla/all-in-one prechecks

kolla-ansible -i /etc/kolla/all-in-one deploy