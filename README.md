# misha-auto-login

This repo now contains a small Python helper for Yale VPN setup tasks. This should be helpful for conducting research in the van Dijk lab.

It does **not** automate:
- Yale username/password submission
- Duo push, passcode, or other MFA approval
- VPN session establishment by bypassing the supported Cisco flow

That boundary is intentional. Automating credential entry or MFA approval for `access.yale.edu` would cross into unsafe territory and may violate Yale security policy.

## Project setup

Create and activate the local Conda environment:

```bash
conda env create -p ./.conda-env -f environment.yml
conda activate ./.conda-env
python -m pip install --upgrade pip
```

## Usage

Check local status:

```bash
python scripts/yale_vpn_helper.py status
```

Open the Yale VPN portal in your browser:

```bash
python scripts/yale_vpn_helper.py open-portal
```

Launch Cisco Secure Client on macOS, if installed:

```bash
python scripts/yale_vpn_helper.py launch-cisco
```

Run the practical start flow:

```bash
python scripts/yale_vpn_helper.py start
```

That command:
- launches Cisco Secure Client
- opens `https://access.yale.edu`
- polls local macOS state for a short time and reports whether a tunnel appears active

You can change the polling duration:

```bash
python scripts/yale_vpn_helper.py start --wait-seconds 30
```

## Notes

- Yale VPN access currently uses Cisco Secure Client / AnyConnect plus Duo MFA.
- Recent Yale guidance indicates the VPN login flow uses the new Duo Universal Prompt.
- If you need deeper automation, the safe path is to check whether Yale ITS provides an officially supported CLI, API, or device-trust workflow for your account type.
- If Conda activation is not initialized in your shell yet, run `conda init zsh` once and restart the shell.

# TODO Steps:
1. connect to yale vpn via cisco anyconnect
2. once the server is ready to be connected (browser automation/webhook), you should open a VS code server programatically with this url (it's okay if you get stuck on the part where i have to confirm via phone)
3. connect again via duo 

ssh-add --apple-use-keychain ~/.ssh/id_ed25519
