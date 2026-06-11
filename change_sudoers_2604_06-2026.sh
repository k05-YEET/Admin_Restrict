#!/bin/bash
#
# Secure sudoers & polkit policy script
# Ubuntu 26.04 (sudo-rs compatible)
#
# Goal:
# - Only root or cpsadmin may manage users
# - Only root or cpsadmin may use GUI user management
# - Preserve normal sudo administration otherwise
#

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/99-custom-rules"
BACKUP="/etc/sudoers.d/99-custom-rules.bak.$(date +%s)"

echo "[INFO] Starting secure sudoers & polkit configuration..."

#--------------------------------------------------
# Detect proper polkit rules directory
#--------------------------------------------------
if [ -d /etc/polkit-1/rules.d ]; then
    POLKIT_DIR="/etc/polkit-1/rules.d"
elif [ -d /usr/share/polkit-1/rules.d ]; then
    POLKIT_DIR="/usr/share/polkit-1/rules.d"
else
    echo "[WARN] No polkit rules.d directory found. Polkit configuration will be skipped."
    POLKIT_DIR=""
fi

if [ -n "$POLKIT_DIR" ]; then
    POLKIT_RULE="$POLKIT_DIR/49-cpsadmin-useradmin.rules"
fi

#--------------------------------------------------
# Backup existing sudoers file
#--------------------------------------------------
if [ -f "$SUDOERS_FILE" ]; then
    echo "[INFO] Backing up existing sudoers file to $BACKUP"
    cp -a "$SUDOERS_FILE" "$BACKUP"
fi

# Ensure sudoers.d exists
mkdir -p /etc/sudoers.d

TMPFILE=$(mktemp)

#--------------------------------------------------
# Write sudoers configuration
#--------------------------------------------------
cat <<'EOF' > "$TMPFILE"
##
## Ubuntu 26.04 sudo-rs compatible restrictions
##

#
# User-management binaries
#
Cmnd_Alias USER_MGMT = \
    /usr/sbin/adduser, \
    /usr/sbin/deluser, \
    /usr/sbin/useradd, \
    /usr/sbin/userdel, \
    /usr/sbin/usermod, \
    /usr/sbin/groupadd, \
    /usr/sbin/groupdel, \
    /usr/sbin/groupmod, \
    /usr/bin/gpasswd, \
    /usr/sbin/newusers, \
    /usr/sbin/chpasswd, \
    /usr/sbin/vipw, \
    /usr/sbin/vigr

#
# Block direct user switching via su
#
Cmnd_Alias ROOT_SHELL = \
    /bin/su, \
    /usr/bin/su

#
# Allow normal administration except:
# - user management commands
# - su
#
%sudo ALL=(ALL:ALL) ALL, !USER_MGMT, !ROOT_SHELL

#
# Full unrestricted administrator
#
cpsadmin ALL=(ALL:ALL) ALL
EOF

#--------------------------------------------------
# Validate syntax
#--------------------------------------------------
if visudo -cf "$TMPFILE"; then
    echo "[INFO] Syntax OK. Installing new sudoers fragment."

    install -m 440 \
            -o root \
            -g root \
            "$TMPFILE" \
            "$SUDOERS_FILE"
else
    echo "[ERROR] visudo syntax validation failed."

    if [ -f "$BACKUP" ]; then
        echo "[INFO] Restoring previous sudoers configuration."
        cp -a "$BACKUP" "$SUDOERS_FILE"
    fi

    rm -f "$TMPFILE"
    exit 1
fi

rm -f "$TMPFILE"

#--------------------------------------------------
# Create Polkit rule
#--------------------------------------------------
if [ -n "${POLKIT_DIR:-}" ]; then

    echo "[INFO] Creating Polkit restriction rule..."

    mkdir -p "$POLKIT_DIR"

    cat <<'EOF' > "$POLKIT_RULE"
polkit.addRule(function(action, subject) {

    var restrictedActions = [

        "org.gnome.controlcenter.user-accounts.administration",

        "org.freedesktop.accounts.user-administration.create",
        "org.freedesktop.accounts.user-administration.delete",

        "org.freedesktop.accounts.create-user",
        "org.freedesktop.accounts.delete-user",

        "org.freedesktop.accounts.change-user-data",
        "org.freedesktop.accounts.change-own-user-data"
    ];

    if (restrictedActions.indexOf(action.id) >= 0) {

        if (subject.user === "cpsadmin") {
            return polkit.Result.YES;
        }

        return polkit.Result.NO;
    }
});
EOF

    chmod 644 "$POLKIT_RULE"
    chown root:root "$POLKIT_RULE"

    systemctl restart polkit 2>/dev/null \
        || systemctl restart polkit.service 2>/dev/null \
        || systemctl restart polkitd 2>/dev/null \
        || echo "[WARN] Could not restart polkit service"

    echo "[INFO] Polkit rule installed."

else
    echo "[WARN] Skipping polkit configuration."
fi

#--------------------------------------------------
# Secure permissions
#--------------------------------------------------
echo "[INFO] Securing permissions..."

chmod 755 /etc/sudoers.d
chown root:root /etc/sudoers.d

if [ -n "${POLKIT_DIR:-}" ]; then
    chmod 755 "$POLKIT_DIR"
    chown root:root "$POLKIT_DIR"
fi

#--------------------------------------------------
# Final verification
#--------------------------------------------------
echo "[INFO] Verifying sudoers..."

if id cpsadmin >/dev/null 2>&1; then
    if sudo -l -U cpsadmin 2>/dev/null | grep -q "ALL"; then
        echo "[OK] cpsadmin unrestricted"
    fi
fi

CURRENT_USER="$(logname 2>/dev/null || true)"

if [ -n "$CURRENT_USER" ]; then
    echo "[INFO] Effective sudo rules for $CURRENT_USER:"
    sudo -l -U "$CURRENT_USER" || true
fi

echo "[DONE] Secure sudoers & polkit configuration complete."
