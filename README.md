# DVSwitch Instance Script

<img src="https://github.com/hardenedpenguin/dvswitch_instance/blob/main/PXL_20250214_230436698.jpg" width="500" height="300">

A shell script to create and configure multiple independent instances of DVSwitch for DMR operation. This script automates the creation of separate configurations, systemd services, and port assignments for each instance.

## Overview

This script creates isolated DVSwitch instances (2 through 5) by:
- Copying and configuring MMDVM_Bridge, DVSwitch, and Analog_Bridge configuration files
- Creating unique port assignments for each instance (automatically checked for availability)
- Generating systemd service files for each instance
- Setting up separate log directories
- Enabling and starting the services

## Prerequisites

- Root or sudo access (required for systemd and file operations)
- DVSwitch already installed with default configurations:
  - `/opt/MMDVM_Bridge/MMDVM_Bridge.ini`
  - `/opt/MMDVM_Bridge/DVSwitch.ini`
  - `/opt/Analog_Bridge/Analog_Bridge.ini`
- Systemd service files present:
  - `/lib/systemd/system/mmdvm_bridge.service`
  - `/lib/systemd/system/analog_bridge.service`
  - `/lib/systemd/system/md380-emu.service`
- `ss` or `netstat` command available (for port checking)
- An editor configured via `$EDITOR` environment variable (defaults to `nano`)

## Usage

```bash
sudo ./dvswitch_instance.sh <instance_number>
```

### Examples

```bash
# Create instance 2
sudo ./dvswitch_instance.sh 2

# Create instance 3
sudo ./dvswitch_instance.sh 3
```

**Note:** Instance numbers must be between 2 and 5 (inclusive).

## What the Script Does

### 1. Creates Directory Structure
- Configuration: `/etc/dvswitch/<instance>/`
- Logs: `/var/log/mmdvm<instance>/` and `/var/log/dvswitch<instance>/`

### 2. Copies Configuration Files
The script copies (if they don't already exist):
- `MMDVM_Bridge.ini` → `/etc/dvswitch/<instance>/MMDVM_Bridge.ini`
- `DVSwitch.ini` → `/etc/dvswitch/<instance>/DVSwitch.ini`
- `Analog_Bridge.ini` → `/etc/dvswitch/<instance>/Analog_Bridge.ini`

### 3. Configures DMR Mode
Automatically disables all modes except DMR in `MMDVM_Bridge.ini`, then enables:
- DMR mode
- DMR Network

### 4. Port Assignment

The script dynamically assigns ports for each instance, ensuring no conflicts:

| Port Type | Base Port | Instance Offset | Calculation |
|-----------|-----------|----------------|-------------|
| DMR TX | 31100 | +20 per instance | `31100 + (instance-1)*20 + offset*2` |
| DMR RX | DMR TX + 3 | N/A | Calculated from DMR TX |
| USRP TX | 32001 | +20 per instance | `32001 + (instance-1)*20 + offset*2` |
| USRP RX | USRP TX + 2000 | N/A | Calculated from USRP TX |
| Local | 62032 | +20 per instance | `62032 + (instance-1)*20 + offset*2` |
| Emulator | 2470 | +20 per instance | `2470 + (instance-1)*20 + offset*2` |

**Example for Instance 2:**
- Instance offset: `(2-1) * 20 = 20`
- DMR TX Port: `31100 + 20 = 31120` (if available)
- DMR RX Port: `31120 + 3 = 31123`
- USRP TX Port: `32001 + 20 = 32021` (if available)
- USRP RX Port: `32021 + 2000 = 34021`

The script checks port availability before assignment and will find an available port if the calculated port is in use.

### 5. Interactive Configuration

For each configuration file, the script will:
1. Display the specific values that need to be set
2. Prompt you to press Enter
3. Open the file in your default editor (`$EDITOR` or `nano`)

**MMDVM_Bridge.ini:**
- **Id:** Unique ID for this instance
- **[Log] -> FilePath:** `/var/log/mmdvm<instance>`
- **[DMR Network] -> Local:** Assigned local port

**DVSwitch.ini:**
- **[DMR] -> TXPort:** Assigned DMR TX port
- **[DMR] -> RXPort:** Assigned DMR RX port
- **[DMR] -> exportTG:** Your talkgroup
- **[STFU] -> StartTG:** Brandmeister talkgroup (if needed)

**Analog_Bridge.ini:**
- **[GENERAL]emulatorAddress:** `127.0.0.1:<emulator_port>`
- **[AMBE_AUDIO]Ports:** `txPort = <DMR_RX_PORT>`, `rxPort = <DMR_TX_PORT>`
- **ambeMod:** DMR
- **repeaterID:** Match essid
- **txTg:** Default talkgroup (optional)
- **[USRP] -> txPort/rxPort:** Assigned USRP TX/RX ports

### 6. Creates Systemd Services

For each service (`mmdvm_bridge`, `analog_bridge`, `md380-emu`), the script:
- Copies the base service file from `/lib/systemd/system/` to `/etc/systemd/system/`
- Appends the instance number to the service name (e.g., `mmdvm_bridge2.service`)
- Updates paths, ports, and log directories specific to the instance
- Reloads systemd daemon

### 7. Enables and Starts Services

After you confirm all configuration files are edited, the script:
- Enables all three services for the instance
- Starts all three services
- Displays confirmation messages

## Post-Installation

After the script completes, you need to:

1. **Create the second public node** by running `sudo asl-menu`
2. **Set up the node for USRP** (no private node needed)
3. **Configure the rxchannel** to match your instance ports:
   ```
   rxchannel = USRP/127.0.0.1:<USRP_RX_PORT>:<USRP_TX_PORT>
   ```

The script will display the exact `rxchannel` value before exiting.

## Service Management

After installation, manage your instance services with:

```bash
# Check status
sudo systemctl status mmdvm_bridge<instance>.service
sudo systemctl status analog_bridge<instance>.service
sudo systemctl status md380-emu<instance>.service

# Stop services
sudo systemctl stop mmdvm_bridge<instance>.service analog_bridge<instance>.service md380-emu<instance>.service

# Restart services
sudo systemctl restart mmdvm_bridge<instance>.service analog_bridge<instance>.service md380-emu<instance>.service
```

## Notes

- The script is currently configured for **DMR mode only**. It can be modified to support other modes (D-STAR, YSF, P25, etc.).
- Port assignments are checked automatically to prevent conflicts with existing services.
- Configuration files are only copied if they don't already exist (won't overwrite existing configs).
- Each instance is completely isolated with its own configuration, logs, and ports.

## License

Copyright (C) 2025 Jory A. Pratt - W5GLE  
Released under the GNU General Public License v2 or later.
