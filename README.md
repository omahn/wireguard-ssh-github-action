# WireGuard SSH

This action creates a WireGuard tunnel between a GitHub Actions runner and a peer under your control to allow direct SSH access to the runner. This enables interactive sessions to allow for deeper debugging and testing.

# Usage

<!-- start usage -->
```yaml
- uses: omahn/wireguard-ssh-github-action@v1.1
  with:
    # Required. IP address of your WireGuard peer.
    peer_ip: ''
    # Required. SSH public key as a string.
    ssh_public_key: ''
    # Port of WireGuard peer.
    peer_port: '51820'
    # Private IP of GitHub peer.
    github_ip: '192.168.192.1'
    # Seconds to wait for SSH connection.
    ssh_connection_timeout: '300'
    # Seconds to timeout SSH session.
    session_timeout: 3600
```

The action will install and configure WireGuard before enabling SSH access. The action output includes the peer configuration to use locally. Copy to `/etc/wireguard/github.conf` and use `sudo wg-quick up github` (or equivalent) to bring up the tunnel. Logins will then be possible to the `${github_ip}` as the `runner` username using the SSH key associated with the specified SSH public key provided in the configuration.
