#!/bin/bash

trap cleanup 2

function cleanup {
echo "Cleaning up..."
sudo rm -rf $VENV_NAME all-in-one /etc/kolla
exit
}

files=("resources/pkg_management" "resources/os" "resources/network" "resources/bash_colors")

if ! [[ -f ${files[0]} ]] \
|| ! [[ -f ${files[1]} ]] \
|| ! [[ -f ${files[2]} ]] \
|| ! [[ -f ${files[3]} ]]; then
    rm -rf resources
    git clone https://github.com/fkia87/resources.git || \
    { echo -e "Error downloading required files from Github.
Check if \"Git\" is installed and your internet connection is OK." >&2; \
    exit 1; }
fi

for file in ${files[@]}; do
    source $file
done

read -p "Enter a name for your virtual environment[test_venv]: " VENV_NAME
[[ "$VENV_NAME" == "" ]] && VENV_NAME=test_venv

find_mainif || exit 3
while :
do
    echo -e "\nInterface ${BLUE}[$MAINIF]${DECOLOR} with IP address \e[1;34m[$(getifip $MAINIF)]\e[0m \
is selected as main external interface for this server."
    read -p "Do you wish to continue? [Y/n]" START
    echo ""
    if [[ $START == "y" ]] || [[ $START == "Y" ]] || [[ $START == "" ]]; then break; fi
    if [[ $START == "n" ]] || [[ $START == "N" ]]; then exit; fi
done

IP=$(getifip ${MAINIF})

echo -e "${BLUE}Enter the name of Neutron interface:"
select NEUTRON_IF in $(find /sys/class/net/ | rev | cut -d / -f1 | rev | sed '/^$/d' | grep -v lo)
do
    [[ "$NEUTRON_IF" == "" ]] && echo "Invalid selection"
    [[ "$NEUTRON_IF" != "" ]] && break
done
echo -e "${DECOLOR}"
read -p  NEUTRON_IF

DISTRO=$(os)

read -p "Enter the name of backeng VG for Cinder[cinder-volumes]: " VG
[[ "$VG" == "" ]] && VG=cinder-volumes

sudo vgs | grep -q $VG || { echo "VG $VG not found."; exit 2; }

sudo apt update && sudo apt upgrade -y

sudo apt -y install python3-dev libffi-dev gcc libssl-dev || \
{ echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

#sudo apt -y install python3-pip

sudo apt -y install python3-venv || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

python3 -m venv $VENV_NAME || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }
source $VENV_NAME/bin/activate || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

pip install -U pip || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

pip install 'ansible>=4,<6' || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

pip install git+https://opendev.org/openstack/kolla-ansible@master || \
{ echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

sudo rm -rf /etc/kolla ./all-in-one
sudo mkdir /etc/kolla

sudo chown $USER:$(id -gn $USER) /etc/kolla

cp -r $VENV_NAME/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/ || \
{ echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

#cp $VENV_NAME/share/kolla-ansible/ansible/inventory/* /etc/kolla/
cp $VENV_NAME/share/kolla-ansible/ansible/inventory/all-in-one . || \
{ echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

kolla-ansible install-deps || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

#sudo mkdir -p /etc/ansible

#cat << EOF | sudo tee -a /etc/ansible/ansible.cfg
#[defaults]
#host_key_checking=False
#pipelining=True
#forks=100
#EOF

cat << EOF | sudo tee -a /etc/kolla/globals.yml
enable_haproxy: "no"
kolla_internal_vip_address: "$IP"
network_interface: "$MAINIF"
neutron_external_interface: "$NEUTRON_IF"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "$VG"
kolla_base_distro: "$DISTRO"
EOF

echo -e "\n${YELLOW}Generating password...${DECOLOR}\n"
kolla-genpwd
echo -e "\n${GREEN}Done!${DECOLOR}\n"

kolla-ansible -i ./all-in-one bootstrap-servers || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

kolla-ansible -i ./all-in-one prechecks || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }

kolla-ansible -i ./all-in-one deploy || { echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup; }