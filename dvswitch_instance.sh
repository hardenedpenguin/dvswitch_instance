#!/bin/sh

# Build multiple instances of dvswitch.
# Copyright (C) 2025 Jory A. Pratt - W5GLE
# Released under the GNU General Public License v2 or later.

# Ensure the script is run as root
[ "$(id -u)" -eq 0 ] || { printf "This script must be run as root or with sudo\n"; exit 1; }

# Get instance number and validate it
if [ -z "$1" ]; then
  printf "Usage: $0 <instance_number>\nExample: $0 2\n"
  exit 1
fi

instance="$1"

case "$instance" in
  2|3|4|5) ;; # Valid instance numbers, do nothing
  *) printf "Instance number must be 2 thrue 5.\n"; exit 1 ;;
esac

# Configuration variables
MMDVM_BRIDGE_CONFIG_DIR="/opt/MMDVM_Bridge"
ANALOG_BRIDGE_CONFIG_DIR="/opt/Analog_Bridge"
DVSWITCH_CONFIG_DIR="/etc/dvswitch/${instance}"
LOG_DIR="/var/log/mmdvm${instance}"
LOG_DIR1="/var/log/dvswitch${instance}"

# Create directories
mkdir -p "$DVSWITCH_CONFIG_DIR" "$LOG_DIR" "$LOG_DIR1"

# Copy config files (only if they don't exist)
cp_if_not_exists() { [ ! -f "$2" ] && cp "$1" "$2"; }
cp_if_not_exists "$MMDVM_BRIDGE_CONFIG_DIR/MMDVM_Bridge.ini" "$DVSWITCH_CONFIG_DIR/MMDVM_Bridge.ini"
cp_if_not_exists "$MMDVM_BRIDGE_CONFIG_DIR/DVSwitch.ini" "$DVSWITCH_CONFIG_DIR/DVSwitch.ini"
cp_if_not_exists "$ANALOG_BRIDGE_CONFIG_DIR/Analog_Bridge.ini" "$DVSWITCH_CONFIG_DIR/Analog_Bridge.ini"

# Disable all modes except DMR
sed -i 's/Enable=1/Enable=0/g' "$DVSWITCH_CONFIG_DIR/MMDVM_Bridge.ini"
sed -i -e '/\[DMR\]/,/\[.*\]/s/Enable=0/Enable=1/' -e '/\[DMR Network\]/,/\[.*\]/s/Enable=0/Enable=1/' "$DVSWITCH_CONFIG_DIR/MMDVM_Bridge.ini"

# Port range and base values
BASE_DMR_PORT=31100
BASE_USRP_PORT=32001
BASE_LOCAL_PORT=62032
BASE_EMU_PORT=2470

# Function to check if a port is in use
is_port_in_use() {
  netstat -tulnp | grep ":$1 " > /dev/null 2>&1
  return $? # 0 if in use, 1 if free
}

# Function to find an available port within a range
find_available_port() {
  local base="$1"
  local offset=0
  local port

  instance_offset=$(( (instance - 1) * 20 )) # Calculate instance offset

  while [ "$offset" -lt 10 ]; do # Try up to 10 ports
    port=$((base + offset * 2 + instance_offset)) # Use instance offset
    if ! is_port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    offset=$((offset + 1))
  done

  printf "No available port found in range for base %d (instance %d)\n" "$base" "$instance"
  exit 1
}

# Assign ports dynamically
DMR_TX_PORT=$(find_available_port "$BASE_DMR_PORT")
DMR_RX_PORT=$((DMR_TX_PORT + 3))  # RX usually 3 higher
USRP_TX_PORT=$(find_available_port "$BASE_USRP_PORT")
USRP_RX_PORT=$((USRP_TX_PORT + 2000)) # USRP RX is offset by 2000
LOCAL_PORT=$(find_available_port "$BASE_LOCAL_PORT")
EMU_PORT=$(find_available_port "$BASE_EMU_PORT")



# Function to edit files (using a heredoc and `nano` or $EDITOR)
edit_file() {
  local filename="$1"
  local changes=$(cat <<EOF
$(case "$filename" in
  MMDVM_Bridge.ini)
    echo "* **Id:** Unique ID for this instance.\n* **[Log] -> FilePath:** \`$LOG_DIR/MMDVM_Bridge.log\`\n* **[DMR Network] -> Local:** \`$LOCAL_PORT\`"
    ;;
  DVSwitch.ini)
    echo "* **[DMR] -> TXPort:** \`$DMR_TX_PORT\`\n* **[DMR] -> RXPort:** \`$DMR_RX_PORT\`\n* **[DMR] -> exportTG:** Your TG\n* **[STFU] -> StartTG:** Brandmeister TG (if needed)"
    ;;
  Analog_Bridge.ini)
    echo "* **[GENERAL]emulatorAddress:** \`127.0.0.1:$EMU_PORT\`\n* **[AMBE_AUDIO]Ports:** \`txPort = $DMR_RX_PORT\`, \`rxPort = $DMR_TX_PORT\`\n* **ambeMod:** DMR\n* ** repeaterID: Match essid\n* **txTg:** Default TG (optional)\n* **[USRP] -> txPort/rxPort:** \`$USRP_TX_PORT\`, \`$USRP_RX_PORT\`"
    ;;
esac)
EOF
)
  printf "Changes needed in %s:\n%s\nPress Enter to edit or Ctrl+C to cancel.\n" "$filename" "$changes"
  read dummy
  nano "$DVSWITCH_CONFIG_DIR/$filename" # Or ${EDITOR:-vi}
}


# Edit config files
for file in MMDVM_Bridge.ini DVSwitch.ini Analog_Bridge.ini; do edit_file "$file"; done

# Copy and modify service files
for service in mmdvm_bridge analog_bridge md380-emu; do
	cp "/lib/systemd/system/${service}.service" "/etc/systemd/system/${service}${instance}.service"
  
	if [ "$service" = "analog_bridge" ]; then
		sed -i "s|/var/log/dvswitch|$LOG_DIR1|g" "/etc/systemd/system/${service}${instance}.service"
		sed -i "s|Starting Analog_Bridge:|Starting Analog_Bridge ${instance}:|g"  "/etc/systemd/system/${service}${instance}.service"
		sed -i "s|/opt/Analog_Bridge/Analog_Bridge.ini|/etc/dvswitch/${instance}/Analog_Bridge.ini|g" "/etc/systemd/system/${service}${instance}.service"
	elif [ "$service" = "mmdvm_bridge" ]; then
		sed -i "/WorkingDirectory=/a Environment=DVSWITCH=/etc/dvswitch/${instance}/DVSwitch.ini" "/etc/systemd/system/${service}${instance}.service"
		sed -i "s|Starting MMDVM_Bridge:|Starting MMDVM_Bridge ${instance}:|g" "/etc/systemd/system/${service}${instance}.service"
		sed -i "s|/opt/MMDVM_Bridge/MMDVM_Bridge.ini|/etc/dvswitch/${instance}/MMDVM_Bridge.ini|g" "/etc/systemd/system/${service}${instance}.service"
	else
		sed -i "s|2470|$EMU_PORT|g" "/etc/systemd/system/${service}${instance}.service"
	fi
done

# Reload systemd
systemctl daemon-reload

# Confirm config edits
while true; do
  printf "Have you modified all three config files? (y/n) "
  read response
  case "$response" in
    y|Y|yes|YES) break ;;
    n|N|no|NO) printf "Modify the config files before proceeding.\n"; exit 1 ;;
    *) printf "Please enter 'y' or 'n'.\n" ;;
  esac
done

# Enable and start services
for service in mmdvm_bridge analog_bridge md380-emu; do
  systemctl enable "${service}${instance}.service"
  systemctl start "${service}${instance}.service"
  printf "Enabled and started %s${instance}.service\n" "$service"
done

# Give users basic instructions for addig second node.
printf "\n"
printf "Now that the instance ${instance} is configured and running you need to create the second public node.\n"
printf "You can run \`sudo asl-menu\` and add the new node, make sure you are setting it up for USRP, there\n"
printf "is no need for a private node here. After creating the node you must match your ports for the switch\n"
printf "instance, \`rxchannel = USRP/127.0.0.1:$USRP_RX_PORT:$USRP_TX_PORT\`\n"