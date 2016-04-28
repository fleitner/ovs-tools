#!/bin/bash
#
# This script will create a number of vlans using network
# namespaces to demonstrate how port mirroring works with
# Open vSwitch.
#
# Author: Flavio Leitner <fbl@redhat.com>
# Date: 27/Apr/2016
# Version: 1.0
#

# Default bridge name
OVSBR="ovsbr0"


function bridge_add() {
    local bridge="$1"

    ovs-vsctl add-br ${bridge}
}

function bridge_del() {
    local bridge="$1"

    ovs-vsctl del-br ${bridge}
}

function vlans_add() {
    local bridge="$1"
    local vlan_start=$2
    local vlan_end=$3

    for vlanid in $(seq ${vlan_start} ${vlan_end})
    do
        # create internal device in the same vlan
        intdev="int${vlanid}"
        ovs-vsctl add-port ${bridge} ${intdev} tag=${vlanid} \
            -- set interface ${intdev} type=internal
        ip link set ${intdev} up
        ip a a 10.10.${vlanid}.1/24 dev ${intdev}

        # create a peer device in the same vlan
        vlandev="vlan${vlanid}"
        ip link add name ${vlandev} type veth peer name veth${vlanid}
        ovs-vsctl add-port ${bridge} ${vlandev} tag=${vlanid}
        ip link set ${vlandev} up
        ip netns add ns${vlanid}
        ip link set veth${vlanid} netns ns${vlanid}
        ip netns exec ns${vlanid} ip a add 10.10.${vlanid}.2/24 dev veth${vlanid}
        ip netns exec ns${vlanid} ip link set veth${vlanid} up

        # run ping between them
        ip netns exec ns${vlanid} ping -q 10.10.${vlanid}.1 &
    done
}

function vlans_del() {
    local bridge="$1"
    local vlan_start=$2
    local vlan_stop=$3

    for vlanid in $(seq ${vlan_start} ${vlan_stop})
    do
        vlandev="vlan${vlanid}"
        pkill --nslist ns${vlanid} ping 2> /dev/null
        ip link del ${vlandev} 2> /dev/null
        ip netns del ns${vlanid} 2> /dev/null
        ovs-vsctl del-port ${bridge} int${vlanid} 2> /dev/null
    done
}

function mirror_port_add() {
    local bridge="$1"

    # create a tap port
    ovs-vsctl add-port ${bridge} tap0 -- set interface tap0 type=internal
    ip link set tap0 up

    # create the mirror for all traffic to go to tap0
    ovs-vsctl -- --id=@tap0 get Port tap0 \
              -- --id=@m create mirror name=0 select-all=true \
                         output-port=@tap0 \
              -- set Bridge ${bridge} mirrors=@m
}

function mirror_port_del() {
    local bridge="$1"

    ovs-vsctl --if-exist clear bridge ${bridge} mirrors
    ovs-vsctl --if-exist del-port tap0
}

function env_clean() {
    local bridge="$1"
    local vlan_start=$2
    local vlan_stop=$3

    vlans_del ${bridge} 0 4096
    mirror_port_del ${bridge}
    bridge_del ${bridge}
}


function usage() {
cat << EOF
Usage: $0 [command] args

Commands:
   clean
   - clean up the environment

   add-br
   - add default ovs bridge

   del-br
   - del default ovs bridge

   add-mirror
   - create the mirror port called tap0

   del-mirror
   - delete the mirror port called tap0

   add-vlans [vlanid_start] [vlanid_stop]
   - create vlan devices starting with vlan tag [vlanid_start] until
     vlan tag [vlanid_stop]

   del-vlans [vlanid_start] [vlanid_stop]
   - create vlan devices starting with vlan tag [vlanid_start] until
     vlan tag [vlanid_stop]
EOF
}

case "$1" in
    clean)
        env_clean ${OVSBR}
        ;;

    add-br)
        bridge_add ${OVSBR}
        ;;

    del-br)
        bridge_del ${OVSBR}
        ;;

    add-mirror)
        mirror_port_add ${OVSBR}
        ;;

    del-mirror)
        mirror_port_del ${OVSBR}
        ;;

    add-vlans)
        vlans_add ${OVSBR} $2 $3
        echo ""
        ;;

    del-vlans)
        vlans_del ${OVSBR} $2 $3
        ;;

    *)
        usage
        exit 1
        ;;
esac


