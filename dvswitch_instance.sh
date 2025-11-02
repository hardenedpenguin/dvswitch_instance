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
  *) printf "Instance number must be 2 through 5.\n"; exit 1 ;;
esac

# Configuration variables
MMDVM_BRIDGE_CONFIG_DIR="/opt/MMDVM_Bridge"
ANALOG_BRIDGE_CONFIG_DIR="/opt/Analog_Bridge"
DVSWITCH_CONFIG_DIR="/etc/dvswitch/${instance}"
MMDVM_LOG_DIR="/var/log/mmdvm${instance}"
DVSWITCH_LOG_DIR="/var/log/dvswitch${instance}"

# Create directories
mkdir -p "$DVSWITCH_CONFIG_DIR" "$MMDVM_LOG_DIR" "$DVSWITCH_LOG_DIR"

# Copy config files (only if they don't exist)
cp_if_not_exists() {
  if [ ! -f "$1" ]; then
    printf "Error: Source file does not exist: %s\n" "$1"
    exit 1
  fi
  if [ ! -f "$2" ]; then
    cp "$1" "$2" || { printf "Error: Failed to copy %s to %s\n" "$1" "$2"; exit 1; }
  fi
}
cp_if_not_exists "$MMDVM_BRIDGE_CONFIG_DIR/MMDVM_Bridge.ini" "$DVSWITCH_CONFIG_DIR/MMDVM_Bridge.ini"
cp_if_not_exists "$MMDVM_BRIDGE_CONFIG_DIR/DVSwitch.ini" "$DVSWITCH_CONFIG_DIR/DVSwitch.ini"
cp_if_not_exists "$ANALOG_BRIDGE_CONFIG_DIR/Analog_Bridge.ini" "$DVSWITCH_CONFIG_DIR/Analog_Bridge.ini"

# Disable all modes except DMR
sed -i -e 's/^Enable=1$/Enable=0/g' \
       -e '/^\[DMR\]$/,/^\[.*\]$/{ /^Enable=0$/s/^Enable=0$/Enable=1/; }' \
       -e '/^\[DMR Network\]$/,/^\[.*\]$/{ /^Enable=0$/s/^Enable=0$/Enable=1/; }' \
       "$DVSWITCH_CONFIG_DIR/MMDVM_Bridge.ini"

# Port range and base values
BASE_DMR_PORT=31100
BASE_USRP_PORT=32001
BASE_LOCAL_PORT=62032
BASE_EMU_PORT=2470
INSTANCE_OFFSET=$(( (instance - 1) * 20 ))

# Function to check if a port is in use
is_port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -tulnp | grep ":$1 " > /dev/null 2>&1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tulnp | grep ":$1 " > /dev/null 2>&1
  else
    printf "Error: Neither 'ss' nor 'netstat' command found. Cannot check port availability.\n"
    exit 1
  fi
  return $?
}

# Function to find an available port within a range
find_available_port() {
  local base="$1" offset=0 port
  while [ "$offset" -lt 10 ]; do
    port=$((base + offset * 2 + INSTANCE_OFFSET))
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
DMR_RX_PORT=$((DMR_TX_PORT + 3))
USRP_TX_PORT=$(find_available_port "$BASE_USRP_PORT")
USRP_RX_PORT=$((USRP_TX_PORT + 2000))
LOCAL_PORT=$(find_available_port "$BASE_LOCAL_PORT")
EMU_PORT=$(find_available_port "$BASE_EMU_PORT")

# Service configuration
SERVICES="mmdvm_bridge analog_bridge md380-emu"
SYSTEMD_SOURCE="/lib/systemd/system"
SYSTEMD_TARGET="/etc/systemd/system"

# Function to edit files
edit_file() {
  local filename="$1"
  local changes=""
  
  case "$filename" in
    MMDVM_Bridge.ini)
      changes="* **Id:** Unique ID for this instance.
* **[Log] -> FilePath:** \`$MMDVM_LOG_DIR\`
* **[DMR Network] -> Local:** \`$LOCAL_PORT\`"
      ;;
    DVSwitch.ini)
      changes="* **[DMR] -> TXPort:** \`$DMR_TX_PORT\`
* **[DMR] -> RXPort:** \`$DMR_RX_PORT\`
* **[DMR] -> exportTG:** Your TG
* **[STFU] -> StartTG:** Brandmeister TG (if needed)"
      ;;
    Analog_Bridge.ini)
      changes="* **[GENERAL]emulatorAddress:** \`127.0.0.1:$EMU_PORT\`
* **[AMBE_AUDIO]Ports:** \`txPort = $DMR_RX_PORT\`, \`rxPort = $DMR_TX_PORT\`
* **ambeMod:** DMR
* **repeaterID:** Match essid
* **txTg:** Default TG (optional)
* **[USRP] -> txPort/rxPort:** \`$USRP_TX_PORT\`, \`$USRP_RX_PORT\`"
      ;;
  esac
  
  printf "Changes needed in %s:\n%s\nPress Enter to edit or Ctrl+C to cancel.\n" "$filename" "$changes"
  read dummy
  ${EDITOR:-nano} "$DVSWITCH_CONFIG_DIR/$filename"
}


# Edit config files
for file in MMDVM_Bridge.ini DVSwitch.ini Analog_Bridge.ini; do
  edit_file "$file"
done

# Copy and modify service files
for service in $SERVICES; do
  service_file="${SYSTEMD_SOURCE}/${service}.service"
  target_file="${SYSTEMD_TARGET}/${service}${instance}.service"
  
  [ ! -f "$service_file" ] && { printf "Error: Service file does not exist: %s\n" "$service_file"; exit 1; }
  cp "$service_file" "$target_file" || { printf "Error: Failed to copy service file for %s\n" "$service"; exit 1; }
  
  case "$service" in
    analog_bridge)
      sed -i -e "s|/var/log/dvswitch|$DVSWITCH_LOG_DIR|g" \
             -e "s|Starting Analog_Bridge:|Starting Analog_Bridge ${instance}:|g" \
             -e "s|/opt/Analog_Bridge/Analog_Bridge.ini|/etc/dvswitch/${instance}/Analog_Bridge.ini|g" \
             "$target_file"
      ;;
    mmdvm_bridge)
      sed -i -e "/WorkingDirectory=/a Environment=DVSWITCH=/etc/dvswitch/${instance}/DVSwitch.ini" \
             -e "s|Starting MMDVM_Bridge:|Starting MMDVM_Bridge ${instance}:|g" \
             -e "s|/opt/MMDVM_Bridge/MMDVM_Bridge.ini|/etc/dvswitch/${instance}/MMDVM_Bridge.ini|g" \
             "$target_file"
      ;;
    *)
      sed -i "s|2470|$EMU_PORT|g" "$target_file"
      ;;
  esac
done

# Reload systemd
systemctl daemon-reload

# Confirm config edits
while true; do
  printf "Have you modified all three config files? (y/n) "
  read response
  case "$response" in
    [Yy]*|[Yy][Ee][Ss]*) break ;;
    [Nn]*|[Nn][Oo]*) printf "Modify the config files before proceeding.\n"; exit 1 ;;
    *) printf "Please enter 'y' or 'n'.\n" ;;
  esac
done

# Enable and start services
for service in $SERVICES; do
  systemctl enable "${service}${instance}.service"
  systemctl start "${service}${instance}.service"
  printf "Enabled and started %s%s.service\n" "$service" "$instance"
done

# Give users basic instructions for adding second node
cat <<EOF

Now that instance ${instance} is configured and running, you need to create the second public node.
You can run \`sudo asl-menu\` and add the new node. Make sure you are setting it up for USRP;
there is no need for a private node here. After creating the node you must match your ports for
the switch instance: \`rxchannel = USRP/127.0.0.1:$USRP_RX_PORT:$USRP_TX_PORT\`.
EOF