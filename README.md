# Admin_Restrict
A script that will restrict sudoers on an Ubuntu OS to a certain extend.
---
change_sudoers_XX-202X.sh bewirkt folgendes:

1. Sperren der Verwaltung der GUI in GNOME für sudoers außer cpsadmin (via Polkit Regel unter /etc/polkit-1/rules.d/\*)
2. Sperren der Bearbeitung (vim, nano, cp, mv, rm, mkdir, ... chown, chmod) für config Ordner bezogen auf einschränkende Files (/etc/sudoers\*, /etc/polkit-1/\*)
3. Sperren der Root Shell (nicht vollständig, umgehbar in dem man eine andere Shell installiert) für normale sudoers (!cpsadmin)
4. Sperren des User-MGMT per shell (blocked: useradd, adduser, deluser, userdel). Gruppen hinzufügen / entfernen ist erlaubt (weil keine Regel auf Gruppen basiert)

Jede Berarbeitung von Regeln unter /etc/sudoers.d/ wird mit visudo ausgeführt und bricht ab wenn ein Check negatives Feedback bekommt zur Sicherheit. Von jedem Ordner / File das verändert wird wird ein Backup vorab abgespeichert:  
/etc/sudoers.d/99-custom-rules.bak.$(date +%s)  
Das main-system File /etc/sudoers wird nicht angerührt.

Runtime ist gering. Kein Zusatzfile nötig.

File: change_sudoers_10-2025.sh - Getestet auf Ubuntu 24.04 LTS in Oktober 2025
File: change_sudoers_01-2026.sh - Getestet auf Ubuntu 24.04 LTS im Fe
