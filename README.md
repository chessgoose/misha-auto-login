# misha-auto-login

One command to go from your laptop to a VS Code session with Claude Code or other agentic coding tools.

> **macOS and Linux only.** Windows is not supported without significant rework (WSL2 + extra setup at minimum).

Due to the exposure risks associated with API coding tools like Claude Code, the YCRC does not formally support researchers who wish to use AI coding tools to aid in their workflow development (https://docs.ycrc.yale.edu/ai/aicodingtools/).

## Prerequisites

- **macOS** or **Linux**
- **Yale VPN** connected, or on Yale WiFi (see [VPN check](#vpn-check) below)
- SSH key with an **empty passphrase**, uploaded to https://sshkeys.ycrc.yale.edu/ (see [YCRC SSH docs](https://docs.ycrc.yale.edu/clusters-at-yale/access/ssh/))
- **Duo Mobile** app installed and enrolled for Yale 2FA (the script auto-sends a Duo Push — you just tap approve)
- **VSCode** with the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension
- `code` CLI in your PATH (VSCode: `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH")
- **`expect`** — pre-installed on macOS; on Linux install it first:
  ```bash
  # Debian/Ubuntu
  sudo apt install expect
  # RHEL/Fedora
  sudo yum install expect
  ```

## Setup

1. Clone the repo:

   ```bash
   git clone https://github.com/chessgoose/misha-auto-login.git
   cd misha-auto-login
   ```

2. Copy the example config and fill in your values:

   ```bash
   cp config.yml.example config.yml
   ```

   Edit `config.yml` with your NetID, working directory, and resource preferences.

## VPN Check

Before running the session script, you must be reachable to `misha.ycrc.yale.edu` — either on Yale WiFi or connected to Yale VPN (Cisco Secure Client).

To check:

```bash
./scripts/ensure_vpn.sh
```

This just verifies reachability and exits with an error if not connected — it does not connect for you. Connect to VPN manually first if needed.

Optionally, set `auto_vpn: true` in `config.yml` to run this check automatically at the start of each session.

## Usage

### Start a session

```bash
./scripts/misha_code_session.sh
```

This will:

1. (Optional) Check Yale network reachability if `auto_vpn: true`
2. Load your SSH key into the agent (no passphrase prompt)
3. Open an SSH connection to the Misha login node, automatically selecting Duo Push
4. Submit a SLURM job with your configured resources
5. Wait for the job to start running
6. Update your `~/.ssh/config` so VSCode can reach the compute node
7. Launch VSCode connected to the compute node — no additional Duo prompt

### Configuration

All options are set in `config.yml`:

| Key                  | Description                                        | Default             |
|----------------------|----------------------------------------------------|---------------------|
| `netid`              | Your Yale NetID                                    | —                   |
| `ssh_key_path`       | Path to your SSH private key                       | `~/.ssh/id_ed25519` |
| `working_directory`  | Remote directory to open in VSCode                 | `~`                 |
| `hours`              | Job duration in hours                              | `2`                 |
| `cpus_per_task`      | Number of CPUs                                     | `1`                 |
| `memory_per_cpu_gib` | Memory per CPU in GiB                              | `32`                |
| `partition`          | SLURM partition                                    | `devel`             |
| `auto_vpn`           | Check Yale network reachability before connecting  | `false`             |
| `auto_cancel`        | Cancel SLURM job when VSCode window closes         | `true`              |
| `reservation`        | SLURM reservation (optional)                       | —                   |
| `custom_command`     | Command to run on compute node before sleep        | —                   |
| `additional_modules` | Space-separated modules to load (optional)         | —                   |

You can also override settings via CLI flags:

```bash
./scripts/misha_code_session.sh --hours 4 --cpus 2 --mem 64 --partition day
```

## How it works

- **SSH key handling**: Uses `SSH_ASKPASS` to feed the empty passphrase to `ssh-add` non-interactively, so the key is loaded into the agent silently.
- **Duo automation**: Uses `expect` to automatically select option 1 (Duo Push) during SSH authentication — you just approve the push on your phone.
- **SSH multiplexing**: Establishes a single authenticated master connection with a persistent control socket. All subsequent SSH commands (SLURM submission, job polling) and VSCode's `ProxyJump` reuse this socket — no repeated Duo prompts.
- **SSH config management**: Writes a managed block to `~/.ssh/config` with `Host misha` (control socket settings) and `Host misha-compute` (ProxyJump to the allocated node). The block is replaced on each run.
