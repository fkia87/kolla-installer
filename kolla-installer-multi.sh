#!/bin/bash

trap cleanup 2 

function cleanup {
echo "Cleaning up..."
kolla-ansible -i ./all-in-one destroy
sudo rm -rf $VENV_NAME all-in-one /etc/kolla
exit
}

function error {
echo -e "\n${RED}Error!${DECOLOR}\n"; cleanup;
}

function usage {
echo ""
echo "Usage:"
echo "  $0 [latest|wallaby]       Install latest or wallaby version"
echo "  $0 [-h|--help]            Show this help"
echo ""
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

echo -e "${GREEN}Sychronizing the time...${DECOLOR}"
sudo systemctl restart systemd-timesyncd

case $1 in
"" | latest)
    version=latest
    ;;
wallaby | Wallaby)
    version=wallaby
    ;;
-h | --help)
    usage
    exit
    ;;
*)
    echo -e "${RED}Invalid version!${DECOLOR}"
    cleanup
    ;;
esac
echo -e "Installing ${BLUE}${BOLD}$version${DECOLOR} version..."

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

[[ $(os) != "ubuntu" ]] && { echo -e "\n${RED}Unsupported distro!${DECOLOR}\n"; cleanup; }
DISTRO=$(os)

read -p "Enter the name of backeng VG for Cinder[cinder-volumes]: " VG
[[ "$VG" == "" ]] && VG=cinder-volumes

sudo vgs | grep -q $VG || { echo "VG $VG not found."; cleanup; }

sudo apt update
# && sudo apt upgrade -y

sudo apt -y install python3-dev libffi-dev gcc libssl-dev || error

#sudo apt -y install python3-pip

sudo apt -y install python3-venv || error

python3 -m venv $VENV_NAME || error
source $VENV_NAME/bin/activate || error

pip install -U pip || error

case $version in
latest)
    pip install 'ansible>=4,<6' || error
    pip install git+https://opendev.org/openstack/kolla-ansible@master || error
    ;;
wallaby)
    pip install 'ansible<3.0' || error
    #pip install git+https://opendev.org/openstack/kolla-ansible@stable/wallaby || error
    pip install 'kolla-ansible<12.9' || error
    ;;
esac

sudo rm -rf /etc/kolla ./all-in-one
sudo mkdir /etc/kolla

sudo chown $USER:$(id -gn $USER) /etc/kolla

cp -r $VENV_NAME/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/ || error

#cp $VENV_NAME/share/kolla-ansible/ansible/inventory/* /etc/kolla/
cp $VENV_NAME/share/kolla-ansible/ansible/inventory/all-in-one . || error

case $version in
latest)
    kolla-ansible install-deps || error
    ;;
esac

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
docker_registry: registry.ficld.ir
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