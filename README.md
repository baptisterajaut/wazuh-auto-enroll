# Wazuh Auto-Enroll

Automated Wazuh agent deployment scripts. Uses a `config.key` file to configure the connection to the Wazuh manager.

## Download

- [wazuh-agent-deploy.sh](https://raw.githubusercontent.com/baptisterajaut/wazuh-auto-enroll/main/wazuh-agent-deploy.sh) — Linux (Debian/RHEL/Arch)
- [wazuh-agent-deploy.bat](https://raw.githubusercontent.com/baptisterajaut/wazuh-auto-enroll/main/wazuh-agent-deploy.bat) — Windows

## config.key

Place a `config.key` file in the same directory as the script:

```ini
manager=wazuh.example.com
password=enrollment_password_here
group=default
```

| Field      | Description                              |
|------------|------------------------------------------|
| `manager`  | Wazuh manager address                    |
| `password` | Agent enrollment password                |
| `group`    | Wazuh agent group                        |
| `name`     | *(optional)* Agent name (default: hostname) |

The `.key` file is private — never commit it.

## Linux

```bash
curl -sO https://raw.githubusercontent.com/baptisterajaut/wazuh-auto-enroll/main/wazuh-agent-deploy.sh
chmod +x wazuh-agent-deploy.sh

# With config.key in the same directory
sudo ./wazuh-agent-deploy.sh

# With a specific key file and custom name
sudo ./wazuh-agent-deploy.sh -k /path/to/my.key -n "Living-Room-PC"
```

Supported: apt (Debian/Ubuntu), yum (RHEL/CentOS), pacman + pikaur/yay (Arch).
If the package manager is not supported (e.g. NixOS), install the agent manually then re-run the script to enroll.

## Windows

1. Download `wazuh-agent-deploy.bat` and `config.key` into the same folder
2. Right-click the `.bat` → **Run as administrator**
3. If no `name` is set in `config.key`, the script will prompt for an agent name (press Enter to use the hostname)

## Linux options

| Option | Description                                  |
|--------|----------------------------------------------|
| `-k`   | Path to `.key` file (default: `config.key` next to the script) |
| `-n`   | Agent name (default: hostname)               |

## Discord alerting

`custom-discord.py` is a drop-in replacement for Wazuh's stock `slack` integration that fixes compatibility with Discord's `/slack` webhook endpoint:

- Adds required top-level `text` field
- Removes unsupported `ts` field
- Falls back to `rule.description` when `full_log` is absent (e.g. vulnerability detector alerts)

Install to `/var/ossec/integrations/custom-discord.py` on the manager, copy the stock `slack` wrapper as `custom-discord`, and set `<name>custom-discord</name>` in `ossec.conf`. Survives Wazuh upgrades.
