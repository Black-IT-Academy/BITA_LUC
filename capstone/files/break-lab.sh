#!/bin/bash
# ---------------------------------------------------------------------------
# BITA capstone fault injector.
#
# Run by setup.sh at first boot. Also safe to re-run by hand to reset the lab
# back to its broken state:   sudo /opt/bita/break-lab.sh
#
# Four faults, all permission/account/service related, all diagnosable from logs.
# ---------------------------------------------------------------------------
set -u

. /opt/bita/lab.env

echo "=== injecting faults: $(date -Is) ==="

# ---------------------------------------------------------------------------
# FAULT 1 - "the password is right but the user still can't log in"
#
#   a) the account is locked in /etc/shadow (usermod -L puts a '!' in front of
#      the hash - the hash itself is untouched, so the password IS correct)
#   b) the login shell is /usr/sbin/nologin
#
# Layer (a) shows up in /var/log/auth.log as:
#     "User bita-user not allowed because account is locked"
# Once unlocked, layer (b) shows up as the nologin banner:
#     "This account is currently not available."
# ---------------------------------------------------------------------------
echo "[fault 1] locking $LAB_USER and setting a nologin shell"
usermod -L "$LAB_USER"
usermod -s /usr/sbin/nologin "$LAB_USER"

# ---------------------------------------------------------------------------
# FAULT 2 - nginx on :8081 will not start, then will not serve
#
#   a) nginx.conf runs the workers as a user that does not exist, so the
#      master process refuses to start at all:
#          nginx: [emerg] getpwnam("bita-broken") failed
#   b) the docroot is root-owned and mode 0700, so once the user directive is
#      fixed the (unprivileged) workers get a 403:
#          [error] ... open() "/var/www/lab8081/index.html" failed (13: Permission denied)
# ---------------------------------------------------------------------------
echo "[fault 2] pointing nginx at a non-existent user and locking the docroot"
sed -i -E 's/^\s*user\s+\S+;/user bita-broken;/' /etc/nginx/nginx.conf
grep -qE '^\s*user\s+bita-broken;' /etc/nginx/nginx.conf || sed -i '1i user bita-broken;' /etc/nginx/nginx.conf

chown -R root:root /var/www/lab8081
chmod 0700 /var/www/lab8081
chmod 0600 /var/www/lab8081/index.html

# Force the failure so `systemctl status nginx` reads "failed", not "running".
systemctl restart nginx 2>/dev/null || true

# ---------------------------------------------------------------------------
# FAULT 3 - apt is broken by file permissions
#
#   a) the repo/sources file is mode 000. Visible in `ls -l`, and it breaks
#      every non-root apt call (apt-cache policy, apt-get update --print-uris
#      as a normal user) with "Could not open file ... Permission denied".
#   b) the http method driver has lost its execute bit. This is the one that
#      also breaks apt for ROOT - root bypasses read/write bits via
#      CAP_DAC_OVERRIDE, but it still needs at least one execute bit to exec
#      a file. Error:
#          E: The method driver /usr/lib/apt/methods/http could not be found.
# ---------------------------------------------------------------------------
echo "[fault 3] wrecking permissions on the apt sources file and method driver"

apt_sources_files() {
    # Ubuntu 24.04 uses deb822 (/etc/apt/sources.list.d/ubuntu.sources),
    # 22.04 and older use /etc/apt/sources.list. Handle both.
    [ -s /etc/apt/sources.list ] && echo /etc/apt/sources.list
    if [ -d /etc/apt/sources.list.d ]; then
        find /etc/apt/sources.list.d -maxdepth 1 -type f \
            \( -name '*.list' -o -name '*.sources' \) -print
    fi
}

for f in $(apt_sources_files); do
    echo "  chmod 000 $f"
    chmod 000 "$f"
done

if [ -f /usr/lib/apt/methods/http ]; then
    echo "  chmod a-x /usr/lib/apt/methods/http"
    chmod a-x /usr/lib/apt/methods/http
fi

# ---------------------------------------------------------------------------
# FAULT 4 - a non-critical service left running and enabled at boot
#
#   The box does not need this service, but it is running now and set to come
#   back on every reboot. The student must BOTH stop it and disable it - a
#   plain `systemctl stop` passes the "not running" check but the service
#   returns after a reboot, so "will not start at boot" stays red until it is
#   also disabled.
#       symptom : systemctl is-active <svc>  -> active
#                 systemctl is-enabled <svc> -> enabled
# ---------------------------------------------------------------------------
echo "[fault 4] starting and enabling $NONCRIT_SERVICE"
systemctl enable --now "$NONCRIT_SERVICE" 2>/dev/null || true

echo "=== faults injected: $(date -Is) ==="
