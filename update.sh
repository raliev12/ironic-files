#!/bin/bash

# This script prepares and boots MCV node.
# Also it can update node as well.
# Default action - update.

# For update node just define user parameters and run ./update.sh
# For create node run script with any parameter, for example ./update.sh create

# User parameters
# Prefixes for detect old and create new node and image
NODE_PREFIX="raliev"
IMAGE_PREFIX="raliev"
# Flavor name for boot new node
FLAVOR_NAME="m1.medium"

# Global variables. Don't touch this
LAST_BUILD=""
NODE_IP=""

get_new_image() {
	echo "Downloading last image..."
	local url='ftp://172.18.160.121/'
	LAST_BUILD=$(curl $url 2>/dev/null | tail -1 | awk '{print $(NF)}')
	if [ -z "$LAST_BUILD" ]; then
		echo "Error - last build file invalid"
		exit 1
	fi
	local last_build_url="$url$LAST_BUILD"
	wget $last_build_url -O /tmp/$LAST_BUILD
}

remove_nodes() {
	echo "Deleting old node..."
        local node_ids=$(nova list | grep "$NODE_PREFIX" | awk '{ print $2 }' )
        local node_id_list=($node_ids)
        local node_ips=$(nova list | grep "$NODE_PREFIX" | awk '{ print $13 }' )
        local node_ip_list=($node_ips)
        NODE_IP=${node_ip_list[0]}

        for node_id in "${node_id_list[@]}"; do
               nova delete $node_id
        done

        local node_info=$(nova list | grep "$NODE_PREFIX" )
        while [ -n "$node_info" ]; do
                echo "Waiting for delete node"
                sleep 1
                node_info=$(nova list | grep "$NODE_PREFIX" )
        done
}

remove_images() {
	echo "Deleting old image..."
        local image_ids=$(glance image-list | grep "$IMAGE_PREFIX" | awk '{ print $2 }' )
        local image_id_list=($image_ids)

	for image_id in "${image_id_list[@]}"; do
		glance image-delete $image_id
	done
}

cleanup() {
	remove_nodes
	remove_images
}

boot_new_node () {
	local build_number=$(echo -e "$LAST_BUILD" | awk -F "\." '{ print $4 }' | awk -F "\-" '{ print $1 }' )
	local image_name="$IMAGE_PREFIX-image-$build_number"
	local node_name="$NODE_PREFIX-node-$build_number"
	
	echo "Creating image..."
	glance image-create --name $image_name --disk-format qcow2 --container-format bare --is-public true --file /tmp/$LAST_BUILD  --progress
	rm /tmp/$LAST_BUILD	

	echo "Creating node..."
	local net_id=$(neutron net-list | grep -w net04 | awk '{print $2;}')
	nova boot --image $image_name --flavor $FLAVOR_NAME --nic net-id=$net_id $node_name

	if [ -z "$NODE_IP" ]; then
		NODE_IP=$(nova floating-ip-create | tail -n +4 | head -n -1 | awk '{print $4}' )
	fi
	sleep 5 
	echo "Associating floating ip $NODE_IP to node $node_name"
	nova floating-ip-associate $node_name $NODE_IP
}


create () {
	get_new_image
	boot_new_node 
}

if [ -z "$1" ]; then
	echo "Updating exist node"
	cleanup
else
	echo "Creating new node"
fi

create

