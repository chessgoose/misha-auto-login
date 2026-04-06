# misha-auto-login

One command to go from your laptop to a VSCode session on Misha.

Reduce the time it takes for you to start doing research, and use Claude Code and other modern dev tools locally while running code on the cluster.

## Prerequisites

- Connected to **Yale VPN** (via Cisco Secure Client)
- SSH key with an **empty passphrase**, uploaded to https://sshkeys.ycrc.yale.edu/ (see [YCRC SSH docs](https://docs.ycrc.yale.edu/clusters-at-yale/access/ssh/))
- **Duo Mobile** app installed on your phone and enrolled for Yale 2FA (the script auto-sends a Duo Push)
- **VSCode** installed with the [Remote-SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension
- `code` CLI available in your PATH (VSCode: `Cmd+Shift+P` → "Shell Command: Install 'code' command in PATH")

## Setup

1. Clone the repo:

   ```bash
   git clone https://github.com/your-username/misha-auto-login.git
   cd misha-auto-login
   ```

2. Copy the example config and fill in your values:

   ```bash
   cp config.yml.example config.yml
   ```

   Edit `config.yml` with your NetID, working directory, and resource preferences.

## Usage

### Start a session

```bash
./scripts/misha_code_session.sh
```

This will:

1. Load your SSH key into the agent (no passphrase prompt)
2. Open an SSH connection to the Misha login node, automatically selecting Duo Push
3. Submit a SLURM job with your configured resources
4. Wait for the job to start running
5. Update your `~/.ssh/config` so VSCode can reach the compute node
6. Launch VSCode connected to the compute node — no additional Duo prompt

### Cancel a session

```bash
./scripts/misha_cancel.sh [JOB_ID]
```

### Configuration

All options are set in `config.yml`:

| Key                  | Description                          | Default  |
|----------------------|--------------------------------------|----------|
| `netid`              | Your Yale NetID                      | —        |
| `ssh_key_path`       | Path to your SSH private key         | `~/.ssh/id_ed25519` |
| `working_directory`  | Remote directory to open in VSCode   | `~`      |
| `hours`              | Job duration in hours                | `2`      |
| `cpus_per_task`      | Number of CPUs                       | `1`      |
| `memory_per_cpu_gib` | Memory per CPU in GiB                | `32`     |
| `partition`          | SLURM partition                      | `devel`  |
| `reservation`        | SLURM reservation (optional)         | —        |
| `custom_command`     | Command to run before sleep (optional)| —       |
| `additional_modules` | Space-separated modules to load (optional) | — |
| `auto_cancel`        | Cancel SLURM job when VSCode window closes | `true` |

You can also override settings via CLI flags:

```bash
./scripts/misha_code_session.sh --hours 4 --cpus 2 --mem 64 --partition day
```

## How it works

- **SSH key handling**: Uses `SSH_ASKPASS` to feed the empty passphrase to `ssh-add` non-interactively, so the key is loaded into the agent silently.
- **Duo automation**: Uses `expect` to automatically select option 1 (Duo Push) during SSH authentication.
- **SSH multiplexing**: Establishes a single authenticated master connection with a persistent control socket. All subsequent SSH commands (SLURM submission, job polling) and VSCode's `ProxyJump` reuse this socket — no repeated auth.
- **SSH config management**: Writes a managed block to `~/.ssh/config` with `Host misha` (control socket settings) and `Host misha-compute` (ProxyJump to the allocated node). The block is replaced on each run.
