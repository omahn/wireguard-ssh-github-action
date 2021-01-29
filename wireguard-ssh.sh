#!/bin/bash

echo "=== WireGuard/SSH GitHub Action ==="

# Validate public key
if ! ssh-keygen -l -f - <<< "${SSH_PUBLIC_KEY}"; then
    echo "Failed to validate SSH public key, aborting."
    exit 1
fi

# Calculate peer IPs
GITHUB_IP=${GITHUB_IP:-192.168.192.1}
PEER_PRIVATE_IP=$(awk -F\. '{print $1"."$2"."$3"."$4+1}' <<< "${GITHUB_IP}")
NETWORK=$(awk -F\. '{print $1"."$2"."$3"."$4-1}' <<< "${GITHUB_IP}")
PEER_PORT=${PEER_PORT:-51820}

# Validate provided GitHub IP
if [[ ! ${GITHUB_IP} =~ ^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([‌​0-4][0-9]|5[0-5]))$ ]]; then
    echo "Failed to validate GitHub IP address, aborting."
    exit 1
fi

# Dependencies
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update
sudo DEBIAN_FRONTEND=noninteractive apt-get -yqq install wireguard-dkms net-tools

# Generate keypairs
wg genkey | tee github-privatekey | wg pubkey > github-publickey
wg genkey | tee peer-privatekey | wg pubkey > peer-publickey

# Generate GitHub side wireguard configuration
cat > github.conf <<EOT
[Interface]
PrivateKey = $(cat github-privatekey)
Address = ${GITHUB_IP}

[Peer]
PublicKey = $(cat peer-publickey)
Endpoint = ${PEER_IP}:${PEER_PORT}
AllowedIPs = ${NETWORK}/30
PersistentKeepalive = 20
EOT
sudo cp github.conf /etc/wireguard

# Bring up tunnel, abort on failure
sudo wg-quick up github || exit 1

# Configure SSH
mkdir ~/.ssh
echo "${SSH_PUBLIC_KEY}" > ~/.ssh/authorized_keys

# Fixup home directory permissions
sudo chown runner:runner /home/runner
sudo chmod o-rwx -R /home/runner
sudo chmod g-rwx -R /home/runner

# Output peer configuration
echo "
=== WireGuard peer configuration ==

[Interface]
ListenPort = ${PEER_PORT}
PrivateKey = $(cat peer-privatekey)
[Peer]
PublicKey = $(cat github-publickey)
AllowedIPs = ${GITHUB_IP}/32
"

# Announce availability and wait for connection
SSH_CONNECTION_TIMEOUT=${SSH_CONNECTION_TIMEOUT:-300}
SESSION_TIMEOUT=${SESSION_TIMEOUT:-3600}
echo "=== Ready - waiting up to ${SSH_CONNECTION_TIMEOUT} seconds for SSH connection ==="

# Wait for a connection, if a connection is established then wait until the
# connection is dropped or for SESSION_TIMEOUT and then end the session. If no connection
# is established at all then drop the session after SSH_CONNECTION_TIMEOUT

while [ "${SSH_CONNECTION_TIMEOUT}" -gt 0 ] ; do
  if netstat -nt |grep -q -E "${GITHUB_IP}:22\\W+${PEER_PRIVATE_IP}:[0-9]+\\W+ESTABLISHED" ; then
    echo "=== SSH connection detected - sleeping for ${SESSION_TIMEOUT} seconds or until SSH session ends ==="
    while [ "${SESSION_TIMEOUT}" -gt 0 ] ; do
        if netstat -nt |grep -q -E "${GITHUB_IP}:22\\W+${PEER_PRIVATE_IP}:[0-9]+\\W+ESTABLISHED" ; then
            # Connection is still up
            SESSION_TIMEOUT=$((SESSION_TIMEOUT - 1))
            sleep 1
        else
            # SSH connection dropped, end the session
            echo "=== SSH connection dropped - ending session ==="
            exit 0
        fi
    done
    # Still connected but session has timed out
    echo "=== Session timed out - ending session ==="
    exit 1
  else
    SSH_CONNECTION_TIMEOUT=$((SSH_CONNECTION_TIMEOUT - 1))
    # Produce output to encourage GitHub Actions to show progress during the run
    echo "."
    sleep 1
  fi
done

# No connection seen
echo "=== No SSH connection - aborting ==="
exit 1
