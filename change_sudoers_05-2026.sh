#!/bin/bash
#
# Secure sudoers & polkit policy script
# Only root or cpsadmin may modify sudoers/polkit files or manage users
# Safe rollback and syntax validation included

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/99-custom-rules"
BACKUP="/etc/sudoers.d/99-custom-rules.bak.$(date +%s)"

echo "[INFO] Starting secure sudoers & polkit configuration..."

#-------------------------
# Detect proper polkit rules directory
#-------------------------
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

#-------------------------
# 1. Backup existing sudoers file
#-------------------------
if [ -f "$SUDOERS_FILE" ]; then
    echo "[INFO] Backing up existing sudoers file to $BACKUP"
    cp "$SUDOERS_FILE" "$BACKUP"
fi

# Ensure sudoers.d exists
mkdir -p /etc/sudoers.d

#-------------------------
# 2. Write new sudoers configuration safely
#-------------------------
TMPFILE=$(mktemp)

cat <<'EOF' > "$TMPFILE"
##
## Secure sudoers restriction file
## Blocks user management, system policy edits, and root shells
##

Cmnd_Alias USER_MGMT = /usr/sbin/adduser, /usr/sbin/deluser, /usr/sbin/userdel

Cmnd_Alias SUDOERS_EDIT = /usr/sbin/visudo, \
/bin/nano /etc/sudoers*, \
/usr/bin/vim /etc/sudoers*, \
/bin/rm /etc/sudoers*, \
/bin/mv /etc/sudoers*, \
/bin/cp /etc/sudoers*, \
/usr/bin/chown /etc/sudoers*, \
/usr/bin/chmod /etc/sudoers*

Cmnd_Alias POLICY_EDIT = /bin/nano /etc/polkit-1/*, \
/usr/bin/vim /etc/polkit-1/*, \
/bin/rm /etc/polkit-1/*, \
/bin/cp /etc/polkit-1/*, \
/bin/mv /etc/polkit-1/*, \
/usr/bin/chmod /etc/polkit-1/*, \
/usr/bin/chown /etc/polkit-1/*

Cmnd_Alias ROOT_SHELL = /bin/su, /usr/bin/su

# %sudo can run anything EXCEPT the above restricted operations
%sudo ALL=(ALL:ALL) ALL, !USER_MGMT, !SUDOERS_EDIT, !POLICY_EDIT, !ROOT_SHELL

# Optional: no password prompts for denied command classes
Defaults!USER_MGMT !authenticate
Defaults!SUDOERS_EDIT !authenticate
Defaults!POLICY_EDIT !authenticate
Defaults!ROOT_SHELL !authenticate

# cpsadmin has full unrestricted rights
cpsadmin ALL=(ALL:ALL) ALL
EOF

# Validate syntax
if visudo -cf "$TMPFILE"; then
    echo "[INFO] Syntax OK. Installing new sudoers fragment."
    cp "$TMPFILE" "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    chown root:root "$SUDOERS_FILE"
else
    echo "[ERROR] visudo syntax validation failed."

    if [ -f "$BACKUP" ]; then
        echo "[INFO] Restoring previous sudoers configuration."
        cp "$BACKUP" "$SUDOERS_FILE"
    fi

    rm -f "$TMPFILE"
    exit 1
fi

rm -f "$TMPFILE"

#-------------------------
# 3. Create Polkit rule
#-------------------------
if [ -n "${POLKIT_DIR:-}" ]; then
    echo "[INFO] Creating Polkit restriction rule..."

    mkdir -p "$POLKIT_DIR"

    cat <<'EOF' > "$POLKIT_RULE"
polkit.addRule(function(action, subject) {

    if (action.id == "org.gnome.controlcenter.user-accounts.administration" ||
        action.id == "org.freedesktop.accounts.user-administration.create" ||
        action.id == "org.freedesktop.accounts.user-administration.delete" ||
        action.id == "org.freedesktop.accounts.create-user" ||
        action.id == "org.freedesktop.accounts.delete-user") {

        if (subject.user == "cpsadmin") {
            return polkit.Result.YES;
        } else {
            return polkit.Result.NO;
        }
    }
});
EOF

    chmod 644 "$POLKIT_RULE"
    chown root:root "$POLKIT_RULE"

    systemctl restart polkit \
        || systemctl restart polkit.service \
        || systemctl restart polkitd \
        || echo "[WARN] Could not restart polkit service"

    echo "[INFO] Polkit rule installed."
else
    echo "[WARN] Skipping polkit configuration."
fi

#-------------------------
# 4. Secure permissions
#-------------------------
echo "[INFO] Securing permissions on sensitive directories..."

chmod 755 /etc/sudoers.d
chown root:root /etc/sudoers.d

if [ -n "${POLKIT_DIR:-}" ]; then
    chmod 755 "$POLKIT_DIR"
    chown root:root "$POLKIT_DIR"
fi

#-------------------------
# 5. Final check
#-------------------------
echo "[INFO] Verifying sudoers..."

if sudo -l -U cpsadmin | grep -q "ALL"; then
    echo "[OK] cpsadmin unrestricted"
fi

user="$(logname)"

if sudo -l -U "$user" | grep -q "USER_MGMT"; then
    echo "[OK] restrictions applied for $user"
fi

echo "[DONE] Secure sudoers & polkit configuration complete."
