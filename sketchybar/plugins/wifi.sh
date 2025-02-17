# #!/bin/bash

# INTERFACE="en0"
# LOG_FILE="/tmp/wifi_debug.log"

# # Redirect all output to log file for debugging
# exec > >(tee -a "$LOG_FILE") 2>&1

# update_wifi() {
#     echo "----------------------------------------"
#     echo "$(date): WiFi update started"
    
#     # Debugging environment
#     echo "Environment Variables:"
#     echo "USER: $USER"
#     echo "HOME: $HOME"
#     echo "NAME: ${NAME:-NOT SET}"
#     echo "PLUGIN_DIR: ${PLUGIN_DIR:-NOT SET}"
    
#     # Verify sketchybar executable
#     if ! command -v sketchybar &> /dev/null; then
#         echo "ERROR: sketchybar command not found"
#         exit 1
#     fi

#     # Network details
#     echo "Network Interface: $INTERFACE"
    
#     # Check IP and network details
#     local ip_address ssid signal_strength

#     # IP Address
#     ip_address=$(ipconfig getifaddr "$INTERFACE")
#     echo "IP Address: ${ip_address:-NO IP ADDRESS}"

#     # SSID
#     # ssid=$(networksetup -getairportnetwork "$INTERFACE" | awk -F': ' '{print $2}')
#     echo "SSID: ${ssid:-NO SSID}"

#     # Signal Strength
#     signal_strength=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep "agrCtlRSSI" | awk '{print $2}')
#     echo "Signal Strength: ${signal_strength:-NO SIGNAL}"

#     # Network statistics
#     local network_stats down_bytes up_bytes
#     network_stats=$(netstat -I "$INTERFACE" -b -n -w 1 | tail -n 1)
    
#     # Extract download and upload bytes
#     down_bytes=$(echo "$network_stats" | awk '{print $7}') || down_bytes=0
#     up_bytes=$(echo "$network_stats" | awk '{print $10}') || up_bytes=0

#     # Convert to MB/s
#     local down up
#     down=$(echo "scale=1; $down_bytes/131072" | bc) || down=0
#     up=$(echo "scale=1; $up_bytes/131072" | bc) || up=0

#     # Determine icon 
#     local icon="wifi.disconnected"
    
#     # Connection status logic
#     if [ -n "$ip_address" ] && [ -n "$ssid" ]; then
#         if [ -z "$signal_strength" ] || [ "$signal_strength" -gt -50 ]; then
#             icon="wifi.high"
#         elif [ "$signal_strength" -gt -70 ]; then
#             icon="wifi.med"
#         else
#             icon="wifi.low"
#         fi
#     fi

#     # Logging
#     echo "Download Speed: ${down} MB/s"
#     echo "Upload Speed: ${up} MB/s"
#     echo "Selected Icon: $icon"

#     # Attempt to update sketchybar
#     if sketchybar --set "${NAME:-wifi}" icon="$icon" label="$ssid ↓${down}MB/s ↑${up}MB/s"; then
#         echo "Sketchybar update successful"
#     else
#         echo "ERROR: Sketchybar update failed"
#     fi

#     echo "Completed update at $(date)"
# }

# # Execute the update function
# update_wifi