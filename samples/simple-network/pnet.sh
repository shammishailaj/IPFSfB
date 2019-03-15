#!/bin/bash
# Copyright 2019 IBM Corp.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#   http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Set environment variable
export PATH=${PWD}/../../.bin:${PWD}:$PATH
export IPFS_PATH=${PWD}/../../.build

# Print the help message.
function printHelper() {
	echo "Usage: "
	echo "  pnet.sh <command> <subcommand>"
	echo "      <command> - one of 'up', 'down' or 'restart'."
	echo "          - 'up' - start and up the network with docker-compose up."
	echo "          - 'down' - stop and clear the network with docker-compose down."
	echo "          - 'restart' - restart the network."
	echo "      <subcommand> - network type, <subcommand=p2p|p2s|p2sp>."
	echo "Flags: "
	echo "  -n <network> - print all available network."
	echo "  -i <imagetag> - the tag for the private network launch (defaults to latest)."
	echo "  -f <composefile> - docker-compose file to be selected (defaults to docker-compose.yml)."
}

# Print all network.
function printNetwork() {
	echo "Usage: "
	echo "  pnet.sh <command> <subcommand>"
	echo "      <command> - <command=up|down|restart> corresponding network based on user choice."
	echo "      <subcommand> - one of 'p2p', 'p2s', or 'p2sp'."
	echo "          - 'p2p' - a peer-to-peer based, private network."
	echo "          - 'p2s' - a peer-to-server based, private network."
	echo "          - 'p2sp' - a peer to server and to peer based, private network."
	echo
	echo "Typically, one can bring up the network through subcommand e.g.:"
	echo
	echo "      ./pnet.sh up p2p"
	echo
}

# Generate swarm key
function generateKey() {
	which swarmkeygen
	if [ "$?" -ne 0 ]; then
		echo "swarmkeygen tool not found, exit."
		exit 1
	fi
	echo "---- Generate swarm.key file using swarmkeygen tool. ----"
	set -x
	swarmkeygen generate >$IPFS_PATH/swarm.key
	res=$?
	set +x
	if [ $res -ne 0 ]; then
		echo "Failed to generate swarm.key file, exit."
		exit 1
	fi
}

# Create containers environment
function createContainers() {
	echo "---- Creat containers for running IPFS. ----"
	for PEER in peer0.example.com peer1.example.com; do
		IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_P2P up --no-start $PEER
	done
}

# Copy swarm key file into container
function copySwarmKey() {
	echo "---- Copy swarm key file into the container file system. ----"
	for PEER in peer0.example.com peer1.example.com; do
		set -x
		docker cp -a $IPFS_PATH/swarm.key $PEER:/var/ipfsfb
		set +x
	done
}

# Start containers
function startContainers() {
	echo "---- Start containers using secret swarm key. ----"
	for PEER in peer0.example.com peer1.example.com; do
		IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_P2P start $PEER
	done
	echo "---- Sleeping 12s to allow network complete booting. ----"
	sleep 12
}

# Set and switch to private network
function switchPrivateNet() {
	echo "---- Configure the private network. ----"
	for PEER in peer0.example.com peer1.example.com; do
		docker exec $PEER ipfs bootstrap rm --all
	done
	PEER_ADDR=$(docker exec peer0.example.com ipfs id -f='<addrs>' | tail -n 1)
	docker exec peer1.example.com ipfs bootstrap add $PEER_ADDR
	PEER_ADDR=$(docker exec peer1.example.com ipfs id -f='<addrs>' | tail -n 1)
	docker exec peer0.example.com ipfs bootstrap add $PEER_ADDR
}

# Restart containers for the private network.
function restartContainers() {
	echo "---- Restart containers for the configured private network. ----"
	for PEER in peer0.example.com peer1.example.com; do
		IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_P2P restart $PEER
	done
}

# General interface for up and running a private network.
function networkUp () {
	if [ -d "$IPFS_PATH" ]; then
		generateKey
		createContainers
		copySwarmKey
		startContainers
		switchPrivateNet
		restartContainers
	fi
}

# Start and up a peer to peer based private network
function p2pUp() {
	set -a
	source $ENV_P2P
	set +a
	networkUp
	IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_P2P up -d --no-deps cli 2>&1
	if [ $? -ne 0 ]; then
		echo "ERROR!!! could not start p2p network, exit."
		exit 1
	fi
}

# Stop and clear peer to peer based private network
function p2pDown() {
	set -a
	source $ENV_P2P
	set +a
	# Bring down the private network, and remove volumes.
	docker-compose -f $COMPOSE_FILE_P2P down --volumes --remove-orphans
	if [ "$COMMAND" != "restart" ]; then
		docker run -v $PWD:/var/ipfsfb --rm ipfsfb/ipfs-tools:$IMAGETAG rm -rf /var/ipfsfb/peer /var/ipfsfb/data /var/ipfsfb/staging
		# Remove local ipfs config.
		rm -rf .ipfs/data .ipfs/staging
		# Remove unwanted key file generated by swarmkeygen tool.
		rm -f $IPFS_PATH/*.key
	fi
}

# Start and up a peer to server based private network
function p2sUp () {
	set -a
	source $ENV_P2S
	set +a
	networkUp
	IMAGE_TAG=$IMAGETAG docker-compose -f $COMPOSE_FILE_P2S up -d --no-deps cli 2>&1
	if [ $? -ne 0 ]; then
		echo "ERROR!!! could not start p2s network, exit."
		exit 1
	fi
}

# Stop and clear peer to server based private network
function p2sDown () {
	set -a
	source $ENV_P2S
	set +a
	# Bring down the private network, and remove volumes.
	docker-compose -f $COMPOSE_FILE_P2S down --volumes --remove-orphans
	if [ "$COMMAND" != "restart" ]; then
		docker run -v $PWD:/var/ipfsfb --rm ipfsfb/ipfs-tools:$IMAGETAG rm -rf /var/ipfsfb/peer /var/ipfsfb/server /var/ipfsfb/data /var/ipfsfb/staging
		# Clean the network cache.
		docker network prune -f
		# Remove local ipfs config.
		rm -rf .ipfs/data .ipfs/staging
		# Remove unwanted key file generated by swarmkeygen tool.
		rm -f $IPFS_PATH/*.key
	fi
}

# Start and up a peer to server and to peer based private network
#function p2spUp () {

#}

# Stop and clear peer to server and to peer based private network
#function p2spDown () {

#}

# Use default docker-compose file
COMPOSE_FILE=docker-compose.yml
# Set networks docker-compose file
COMPOSE_FILE_P2P=./p2p/${COMPOSE_FILE}
COMPOSE_FILE_P2S=./p2s/${COMPOSE_FILE}
COMPOSE_FILE_P2SP=./p2sp/${COMPOSE_FILE}
# Environment file
ENV=.env
# Set environment variable for docker-compose file
ENV_P2P=./p2p/${ENV}
ENV_P2S=./p2s/${ENV}
ENV_P2SP=./p2sp/${ENV}
# Set image tag
IMAGETAG=latest

# Options for running command
while getopts "h?n?i:f:" opt; do
	case "$opt" in
	h | \?)
		printHelper
		exit 0
		;;
	n)
		printNetwork
		exit 0
		;;
	i)
		IMAGETAG=$OPTARG
		;;
	f)
		COMPOSE_FILE=$OPTARG
		;;
	esac
done

# The arg of the command
COMMAND=$1
SUBCOMMAND=$2
shift

# Command interface for execution
if [ "${COMMAND}" == "up" ]; then
	if [ "${SUBCOMMAND}" == "p2p" ]; then
		p2pUp
	elif [ "${SUBCOMMAND}" == "p2s" ]; then
		p2sUp
	elif [ "${SUBCOMMAND}" == "p2sp" ]; then
		p2spUp
	else
		printNetwork
		exit 1
	fi
elif [ "${COMMAND}" == "down" ]; then
	if [ "${SUBCOMMAND}" == "p2p" ]; then
		p2pDown
	elif [ "${SUBCOMMAND}" == "p2s" ]; then
		p2sDown
	elif [ "${SUBCOMMAND}" == "p2sp" ]; then
		p2spDown
	else
		printNetwork
		exit 1
	fi
elif [ "${COMMAND}" == "restart" ]; then
	if [ "${SUBCOMMAND}" == "p2p" ]; then
		p2pDown
		p2pUp
	elif [ "${SUBCOMMAND}" == "p2s" ]; then
		p2sDown
		p2sUp
	elif [ "${SUBCOMMAND}" == "p2sp" ]; then
		p2spDown
		p2spUp
	else
		printNetwork
		exit 1
	fi
else
	printHelper
	exit 1
fi