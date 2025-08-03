#!/bin/bash

# Proxmox Resource Access Script
# This script allows you to list VMs and LXC containers on the Proxmox server
# and connect to them directly since it's running on the host.
# Assumptions:
# - Run this script as a user with sufficient privileges (e.g., root).
# - For LXC containers: Uses 'pct enter' for direct shell access.
# - For VMs: 
#   - Tries to use QEMU guest agent to fetch IP and connect via SSH.
#     - Requires qemu-guest-agent installed and running in the VM.
#     - SSH must be enabled in the VM.
#     - Assumes the host can reach the VM's IP (e.g., via bridge network).
#   - Falls back to serial terminal if agent not available and serial is enabled.
#     - Requires serial console enabled on the VM (qm set <ID> -serial0 socket) and configured in guest OS.

# Fetch lists
VM_LIST=$(qm list 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Unable to run qm list. Check permissions."
    exit 1
fi
CT_LIST=$(pct list 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Error: Unable to run pct list. Check permissions."
    exit 1
fi

# Display list
echo "Available Resources:"
echo -e "ID\tType\tName\t\tStatus"
echo "${VM_LIST}" | tail -n +2 | awk '{printf "%s\tVM\t%s\t\t%s\n", $1, $2, $3}'
echo "${CT_LIST}" | tail -n +2 | awk '{printf "%s\tCT\t%s\t\t%s\n", $1, $3, $2}'

# Prompt for ID
read -p "Enter the ID of the resource to connect to: " ID

# Determine type
if echo "${VM_LIST}" | grep -q "^${ID} "; then
    TYPE="VM"
elif echo "${CT_LIST}" | grep -q "^${ID} "; then
    TYPE="CT"
else
    echo "Error: Invalid ID."
    exit 1
fi

if [ "${TYPE}" == "CT" ]; then
    echo "Connecting to LXC container ${ID}..."
    pct enter ${ID}
else
    # VM connection
    # Check if guest agent is available
    qm agent ${ID} ping >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        AGENT_OUTPUT=$(qm agent ${ID} network-get-interfaces)
        IP=$(echo "${AGENT_OUTPUT}" | grep -o '"ip-address": "[^"]*"' | cut -d'"' -f4 | grep -vE '^127\.|^fe80:|^::1$' | head -1)
        if [ -n "${IP}" ]; then
            read -p "Enter username for VM (default: root): " GUEST_USER
            GUEST_USER=${GUEST_USER:-root}
            echo "Connecting to VM ${ID} at ${IP} via SSH..."
            ssh ${GUEST_USER}@${IP}
            exit 0
        else
            echo "No suitable IP address found via guest agent."
        fi
    else
        echo "QEMU guest agent not available."
    fi

    # Fallback to serial terminal
    if qm config ${ID} | grep -q '^serial0:'; then
        echo "Connecting via serial terminal..."
        qm terminal ${ID}
    else
        echo "Error: No connection method available. Ensure qemu-guest-agent is installed/running in the VM or enable serial console."
    fi
fi