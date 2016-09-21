#!/bin/bash

echo ""
echo "This script configures the virtual machine for your MCA/ECA lab"
echo "group. To start, please enter your blackboard group number. If"
echo "you've already run the script, you should not need to run it"
echo "again."

while true
do

    echo ""
    echo "Enter your group number:"
    read groupnr
    echo ""
    
    re='^[1-9][0-9]?$'
    if ! [[ $groupnr =~ $re ]]
    then
        echo "Invalid group number."
        continue
    fi
    
    break
    
done

echo "Saving group number..."
if python3 /home/user/scripts/setgroup.py $groupnr
then
    echo ""
else
    echo ""
    echo "As you can see, an error occurred. Please contact the lab"
    echo "assistents and copypaste the error message. Use"
    echo "ctrl+shift+c to copy the message to clipboard. Press enter"
    echo "to close this terminal."
    read dummy
    exit 1
fi

echo "Now please enter your netID. This is used to set up the VPN"
echo "connection that you will need to run synthesis for assignment"
echo "2 when you're not on the campus network. You can activate the"
echo "connection by clicking the network icon in the system tray"
echo "(diagonal line with a thick part in the middle) and then"
echo "selecting TU-Delft-VPN. This will query only your NetID"
echo "password."
echo ""
echo "Please enter your NetID:"
read netid
echo ""

netid="$(echo "$netid" | cut -d@ -f1)@tudelft.nl"

echo "Modifying VPN configuration for $netid..."

echo "[connection]" > vpn-config
echo "id=TU-Delft-VPN" >> vpn-config
echo "uuid=bfe05791-106f-461d-af90-4c64d8f66079" >> vpn-config
echo "type=vpn" >> vpn-config
echo "permissions=user:user:;" >> vpn-config
echo "" >> vpn-config
echo "[vpn]" >> vpn-config
echo "service-type=org.freedesktop.NetworkManager.vpnc" >> vpn-config
echo "NAT Traversal Mode=natt" >> vpn-config
echo "IPSec secret-flags=1" >> vpn-config
echo "Vendor=cisco" >> vpn-config
echo "Xauth username=$netid" >> vpn-config
echo "IPSec gateway=luchtbrug.tudelft.nl" >> vpn-config
echo "Xauth password-flags=2" >> vpn-config
echo "IPSec ID=public" >> vpn-config
echo "Perfect Forward Secrecy=server" >> vpn-config
echo "IKE DH Group=dh2" >> vpn-config
echo "Local Port=0" >> vpn-config
echo "" >> vpn-config
echo "[ipv4]" >> vpn-config
echo "method=auto" >> vpn-config

sudo mv vpn-config /etc/NetworkManager/system-connections/TU-Delft-VPN
sudo chown root:root /etc/NetworkManager/system-connections/TU-Delft-VPN
sudo chmod 600 /etc/NetworkManager/system-connections/TU-Delft-VPN

sudo nmcli -p c reload

echo "Done. Press enter to close this terminal."
read dummy

