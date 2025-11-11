#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# create-user.sh — Interactive helper to create a non-root sudo user,
#                  harden SSH, and migrate root SSH keys.
#
# Works on modern Ubuntu (20.04/22.04) but should be portable to most
# systemd-based Linux distributions that ship OpenSSH and use /etc/ssh/sshd_config.
# -----------------------------------------------------------------------------

# ----------------------------------------------------------------------
#  Safety rails
# ----------------------------------------------------------------------
set -euo pipefail
# -e  : exit immediately on non-zero status
# -u  : treat unset variables as errors
# -o pipefail : fail a pipeline if any component command fails

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -yq zsh eza

ZSH_BIN="$(command -v zsh || true)"

# Add zsh to /etc/shells if missing
if [[ -n "$ZSH_BIN" && ! $(grep -Fx "$ZSH_BIN" /etc/shells) ]]; then
  echo "$ZSH_BIN" >> /etc/shells
fi


# ----------------------------------------------------------------------
#  1. Ask for a valid *new* username
# ----------------------------------------------------------------------
while true; do
    read -rp "Enter a username you want to login as: " username
    # Username rules: must start with a lowercase letter, followed by
    # lowercase letters, digits, hyphens or underscores.
    if [[ "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; then
        break
    else
        echo "⚠️  Invalid username. Use lowercase letters, digits, underscores; must start with a letter."
    fi
done

# ----------------------------------------------------------------------
#  2. Read and confirm the password for the new user
# ----------------------------------------------------------------------
while true; do
    # -s  : silent (no echo)
    read -rsp "Enter a password for that user: " password1; echo
    read -rsp "Confirm password: "               password2; echo
    if [[ "$password1" == "$password2" && -n "$password1" ]]; then
        break
    else
        echo "⚠️  Passwords do not match. Please try again."
    fi
done

read -rp "Enter the domain name you want to use: (you should already own it): " domain; echo

# ----------------------------------------------------------------------
#  3. Abort early if the user already exists
# ----------------------------------------------------------------------
if id "$username" &>/dev/null; then
    echo "❌ User $username already exists." >&2
    exit 1
fi

# ----------------------------------------------------------------------
#  4. Create the user with a bash login shell and add to sudoers
# ----------------------------------------------------------------------
default_shell="/bin/bash"
[[ -x "$ZSH_BIN" ]] && default_shell="$ZSH_BIN"

useradd --create-home --shell "$default_shell" "$username"

echo "${username}:${password1}" | chpasswd
usermod -aG sudo "$username"
usermod -aG docker "$username"

# ----------------------------------------------------------------------
#  5. Prepare the user’s ~/.ssh directory and copy root’s keys
# ----------------------------------------------------------------------
mkdir -p /home/"$username"/.ssh
chmod 700 /home/"$username"/.ssh

# Copy root’s authorized_keys so the new user can SSH using the same key(s)
cp /root/.ssh/authorized_keys /home/"$username"/.ssh/authorized_keys

chmod 600 /home/"$username"/.ssh/authorized_keys
chown -R "$username":"$username" /home/"$username"/.ssh

# ----------------------------------------------------------------------
#  6. Prep ZSH
# ----------------------------------------------------------------------
if [[ -x "$ZSH_BIN" ]]; then
  cat > /home/"$username"/.zshrc <<'EOF'
# ~/.zshrc – minimal starter file
export HISTFILE=~/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt inc_append_history share_history
alias la='eza -la'
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
EOF
  chown "$username":"$username" /home/"$username"/.zshrc
fi


# ----------------------------------------------------------------------
#  7. Harden SSH daemon configuration
# ----------------------------------------------------------------------
SSHCFG='/etc/ssh/sshd_config'                 # main sshd config
CLOUDINIT='/etc/ssh/sshd_config.d/50-cloud-init.conf' # cloud-init drop-in

patch_line() {
  # Replace or append a key/value pair in sshd_config.
  # Usage: patch_line <Directive> <Value>
  local key=$1
  local value=$2

  # If the directive exists (commented or not), replace the line;
  # otherwise append it at the end of the file.
  if grep -qiE "^\s*#?\s*${key}\s+" "$SSHCFG"; then
    sed -Ei "s|^\s*#?\s*${key}\s+.*|${key} ${value}|I" "$SSHCFG"
  else
    echo "${key} ${value}" >> "$SSHCFG"
  fi
}

# Disable password auth & root login; disable PAM to avoid bypass
patch_line "PasswordAuthentication" "no"
patch_line "PermitRootLogin"        "no"
patch_line "UsePAM"                 "no"

# Remove cloud-init override file (if present) so it can’t re-enable passwords
if [[ -f $CLOUDINIT ]]; then
    rm -f "$CLOUDINIT"
fi

# ----------------------------------------------------------------------
#  7. Validate and reload sshd
# ----------------------------------------------------------------------
/usr/sbin/sshd -t          # syntax check; exits non-zero if invalid
systemctl restart ssh      # graceful restart (Ubuntu service name)

echo "✅ User $username created and SSH hardened successfully."
echo "Log off and then ssh back into the server as $username."

cp caddy/example.env caddy/.env
cp watchtower/example.env watchtower/.env

MEILI_MASTER_KEY="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9')"
NEXTAUTH_SECRET="$(openssl rand -base64 36)"
SEARXNG_SECRET="$(openssl rand -base64 36)"
POSTGRES_PASSWORD="$(openssl rand -base64 36)"
WEBUI_SECRET="$(openssl rand -base64 36)"

sed \
    -e "s|meilimasterkey|${MEILI_MASTER_KEY}|" \
    -e "s|nextauthsecret|${NEXTAUTH_SECRET}|" \
    -e "s|mydomain.com|${domain}|g" \
    karakeep/example.env > karakeep/.env
sed -e "s|mydomain.com|${domain}|g" caddy/Caddyfile.example > caddy/Caddyfile
sed -e "s|mydomain.com|${domain}|g" n8n/example.env > n8n/.env
sed -e "s|mydomain.com|${domain}|g" searxng/example.env > searxng/.env
sed -e "s|mydomain.com|${domain}|g" -e "s|webuisecret|${WEBUI_SECRET}|" openwebui/example.env > openwebui/.env
sed -e "s|searxngsecret|${SEARXNG_SECRET}|g" searxng/config/settings.yml.example > searxng/config/settings.yml
sed -e "s|postgrespassword|${POSTGRES_PASSWORD}|g" postgres/example.env > postgres/.env


cd ~
mv homelab /home/$username/homelab
chown -R $username:$username /home/$username/homelab

mkdir /home/$username/.config
chown -R $username:$username /home/$username/.config
