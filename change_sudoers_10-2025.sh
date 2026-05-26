#!/bin/bash
#
# Secure sudoers & polkit policy script
# Only root or cpsadmin may modify sudoers/polkit files or manage users
# Safe rollback and syntax validation included

set -euo pipefail

SUDOERS_FILE="/etc/sudoers.d/99-custom-rules"
POLKIT_RULE="/etc/polkit-1/rules.d/49-cpsadmin-useradmin.rules"
BACKUP="/etc/sudoers.d/99-custom-rules.bak.$(date +%s)"

echo "[INFO] Starting secure sudoers & polkit configuration..."

#-------------------------
# 1. Backup existing sudoers file
#-------------------------
if [ -f "$SUDOERS_FILE" ]; then
    echo "[INFO] Backing up existing sudoers file to $BACKUP"
    cp "$SUDOERS_FILE" "$BACKUP"
fi

#-------------------------
# 2. Write new sudoers configuration safely
#-------------------------
TMPFILE=$(mktemp)
cat <<'EOF' > "$TMPFILE"
##
## Secure sudoers restriction file
## Blocks user management, system policy edits, and root shells
##

Cmnd_Alias USER_MGMT = /usr/sbin/adduser, /usr/sbin/deluser, /usr/sbin/deluser, /usr/sbin/userdel
Cmnd_Alias SUDOERS_EDIT = /usr/sbin/visudo, /bin/nano /etc/sudoers*, /usr/bin/vim /etc/sudoers*, /bin/rm /etc/sudoers*, /bin/mv /etc/sudoers*, /bin/cp /etc/sudoers*, /usr/bin/chown /etc/sudoers*, /usr/bin/chmod /etc/sudoers*
Cmnd_Alias POLICY_EDIT = /bin/nano /etc/polkit-1/*, /usr/bin/vim /etc/polkit-1/*, /bin/rm /etc/polkit-1/*, /bin/cp /etc/polkit-1/*, /bin/mv /etc/polkit-1/*, /usr/bin/chmod /etc/polkit-1/*, /usr/bin/chown /etc/polkit-1/*
Cmnd_Alias ROOT_SHELL = /bin/su, /bin/su -, /bin/bash -, /usr/bin/su, /usr/bin/bash -

# %sudo can run anything EXCEPT the above restricted operations
%sudo ALL=(ALL:ALL) ALL, !USER_MGMT, !SUDOERS_EDIT, !POLICY_EDIT, !ROOT_SHELL

# Do not prompt for password denial lists (for clarity, optional)
Defaults!USER_MGMT !authenticate
Defaults!SUDOERS_EDIT !authenticate
Defaults!POLICY_EDIT !authenticate
Defaults!ROOT_SHELL !authenticate

# cpsadmin has full rights
cpsadmin ALL=(ALL:ALL) ALL
EOF

# Validate syntax
if visudo -cf "$TMPFILE"; then
    echo "[INFO] Syntax OK. Installing new sudoers fragment."
    cp "$TMPFILE" "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
else
    echo "[ERROR] visudo syntax validation failed. Restoring previous version."
    [ -f "$BACKUP" ] && cp "$BACKUP" "$SUDOERS_FILE"
    exit 1
fi
rm -f "$TMPFILE"

#-------------------------
# 3. Create Polkit rule
#-------------------------
echo "[INFO] Creating Polkit restriction rule..."

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
systemctl restart polkit
echo "[INFO] Polkit rule installed and Polkit restarted."

#-------------------------
# 4. Secure permissions
#-------------------------
echo "[INFO] Securing permissions on sensitive directories..."
chmod 755 /etc/sudoers.d
chmod 755 /etc/polkit-1/rules.d
chown root:root /etc/sudoers.d /etc/polkit-1/rules.d

#-------------------------
# 5. Final check
#-------------------------
echo "[INFO] Verifying sudoers..."
sudo -l -U cpsadmin | grep -q "ALL" && echo "[OK] cpsadmin unrestricted"
sudo -l -U $(logname) | grep -q "USER_MGMT" && echo "[OK] restrictions applied for $(logname)"

echo "[DONE] Secure sudoers & polkit configuration complete."
