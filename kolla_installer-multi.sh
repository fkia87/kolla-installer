#!/bin/bash

trap cleanup 2 

function cleanup {
echo "Cleaning up..."
kolla-ansible -i ./all-in-one destroy > /dev/null 2>&1
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

[[ $(os) != "ubuntu" ]] && { echo -e "\n${RED}Unsupported distro!${DECOLOR}\n"; cleanup; }
DISTRO=$(os)

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

while [[ "$VIP" == "" ]]
do
    read -p "Enter kolla internal VIP address : " VIP
done

while [[ "$IF" == "" ]]
do
    read -p "Enter the name of main interface : " IF
done

while [[ "$NEUTRON_IF" == "" ]]
do
    read -p "Enter the name of Neutron interface : " NEUTRON_IF
done

read -p "Enter the name of backeng VG for Cinder[cinder-volumes]: " VG
[[ "$VG" == "" ]] && VG=cinder-volumes

sudo apt update && sudo apt -y install python3-dev libffi-dev gcc libssl-dev || error

#sudo apt -y install python3-pip

sudo apt -y install python3-venv ansible sshpass|| error

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
    pip install 'kolla-ansible<12.9' || error
    ;;
esac

sudo rm -rf /etc/kolla ./all-in-one
sudo mkdir /etc/kolla
sudo chown $USER:$(id -gn $USER) /etc/kolla
cp -r $VENV_NAME/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/ || error
cp $VENV_NAME/share/kolla-ansible/ansible/inventory/* . || error

sed -i '/StrictHostKeyChecking/d' /etc/ssh/ssh_config
echo '    StrictHostKeyChecking no' | sudo tee -a /etc/ssh/ssh_config

echo -e "${GREEN}${BOLD}So far so good."
echo -e "Press ${UGREEN}Enter${GREEN} to test the inventory...${DECOLOR}"
read TEST

ansible -i ./multinode all -m ping || error

case $version in
latest)
    kolla-ansible install-deps || error
    ;;
esac

#cat << EOF | sudo tee -a /etc/ansible/ansible.cfg
#[defaults]
#host_key_checking=False
#pipelining=True
#forks=100
#EOF

cat << EOF | sudo tee -a /etc/kolla/globals.yml
enable_haproxy: "no"
kolla_internal_vip_address: "$VIP"
docker_registry: registry.ficld.ir
network_interface: "$IF"
neutron_external_interface: "$NEUTRON_IF"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "$VG"
kolla_base_distro: "$DISTRO"
EOF

echo -e "\n${YELLOW}Generating password...${DECOLOR}\n"
kolla-genpwd
echo -e "\n${GREEN}Done!${DECOLOR}\n"

echo -e "${GREEN}${BOLD}So far so good."
echo -e "Press ${UGREEN}Enter${GREEN} to bootstrap...${DECOLOR}"
read TEST
kolla-ansible -i ./multinode bootstrap-servers || \
{ echo -e "${RED}Exit code is $?.${DECOLOR}"; read -p "Continue?" TEST; }

kolla-ansible -i ./multinode prechecks || \
{ echo -e "${RED}Exit code is $?.${DECOLOR}"; read -p "Continue?" TEST; }

kolla-ansible -i ./multinode deploy || \
{ echo -e "${RED}Exit code is $?.${DECOLOR}"; read -p "Continue?" TEST; }

echo -e "${GREEN}${BOLD}So far so good."
echo -e "Press ${UGREEN}Enter${GREEN} to install \"python-openstackclient\"...${DECOLOR}"
read TEST
case $version in
latest)
    pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
    ;;
wallaby)
    pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/wallaby
    ;;
esac

kolla-ansible post-deploy|| \
{ echo -e "${RED}Exit code is $?.${DECOLOR}"; read -p "Continue?" TEST; }

source /etc/kolla/admin-openrc.sh

$VENV_NAME/share/kolla-ansible/init-runonce

PASSWORD=$(grep "keystone_admin_password" /etc/kolla/passwords.yml | awk {'print$2'})
echo -e "${BGREEN}"
echo "###################### Configuration is Done ######################"
echo ""
echo "Horizon URL: http://$IP"
echo "Login:    \"admin\""
echo "Password: \"$PASSWORD\""
echo ""
echo "###################################################################"
echo -e "${DECOLOR}"