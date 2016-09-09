#!/bin/bash

echo ""
echo "This script sets up the TU Delft VPN. You need the VPN to use"
echo "Modelsim and ISE (for synthesis only) when you're not working"
echo "from the campus. You can activate the connection by clicking"
echo "the network icon in the system tray (diagonal line with a"
echo "thick part in the middle) and then selecting TU-Delft-VPN."
echo "This will query only your NetID password. This script changes"
echo "the username."
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

