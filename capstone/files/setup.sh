#!/bin/bash
# ---------------------------------------------------------------------------
# BITA capstone lab provisioner.
#
# Runs once at first boot. Builds a fully WORKING box, proves it works, then
# calls break-lab.sh to introduce the four faults students must diagnose.
# Anything installed here is installed BEFORE apt is sabotaged, on purpose:
# students must troubleshoot with the tooling that is already on the box.
# ---------------------------------------------------------------------------
set -u
exec 2>&1
echo "=== bita setup starting: $(date -Is) ==="

# shellcheck disable=SC1091
. /opt/bita/lab.env

export DEBIAN_FRONTEND=noninteractive

# --- 1. Wait for egress -----------------------------------------------------
# These boxes have no public IP; all egress is NAT'd through the VPN host,
# which may still be booting. Wait for it rather than failing the build.
#
# Probe whichever mirror cloud-init actually selected, not a hardcoded host.
# cloud-init searches a mirror list and writes the winner into ubuntu.sources.
# Hardcoding archive.ubuntu.com meant a Canonical archive outage failed every
# probe, burned the full 90 x 10s, and then continued anyway - 15 dead minutes
# per box while egress was in fact fine the whole time.
echo "--- waiting for outbound network via the NAT/VPN host ---"

. /etc/os-release
CODENAME=${VERSION_CODENAME:-noble}

# First URIs: line of the deb822 sources is the archive cloud-init chose.
MIRROR=$(awk '/^URIs:/ {print $2; exit}' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null)

egress_up() {
    for base in "$MIRROR" http://mirror.math.princeton.edu/pub/ubuntu http://archive.ubuntu.com/ubuntu; do
        [ -n "$base" ] || continue
        if curl -fsS -m 5 -o /dev/null "$base/dists/$CODENAME/Release"; then
            echo "egress up via $base"
            return 0
        fi
    done
    return 1
}

for attempt in $(seq 1 90); do
    if egress_up; then
        echo "egress confirmed after $attempt attempt(s)"
        break
    fi
    sleep 10
done

# --- 2. Base packages -------------------------------------------------------
apt_retry() {
    for attempt in $(seq 1 5); do
        if apt-get "$@"; then
            return 0
        fi
        echo "apt-get $* failed (attempt $attempt), retrying in 15s"
        sleep 15
    done
    return 1
}

echo "--- installing packages ---"
apt_retry update
apt_retry install -y --no-install-recommends \
    nginx \
    curl \
    less \
    vim \
    net-tools \
    lsof \
    tree \
    jq \
    acl \
    man-db \
    bash-completion \
    python3 \
    at

# Keep the lab deterministic: no background apt runs fighting for the lock
# and no surprise package changes mid-exercise.
systemctl disable --now unattended-upgrades.service 2>/dev/null
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null

# --- 3. Accounts ------------------------------------------------------------
echo "--- creating accounts ---"

# Full-sudo admin account handed out in the terraform output.
if ! id -u "$ADMIN_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "BITA lab admin" "$ADMIN_USER"
fi
usermod -aG sudo "$ADMIN_USER"
printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_PASS" | chpasswd
printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$ADMIN_USER" > /etc/sudoers.d/90-bita-admin
chmod 0440 /etc/sudoers.d/90-bita-admin
/usr/sbin/visudo -cf /etc/sudoers.d/90-bita-admin

# The account students must repair. Password is CORRECT and stays correct -
# the fault injected later is an account/shell problem, not a password problem.
if ! id -u "$LAB_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "BITA lab user" "$LAB_USER"
fi
printf '%s:%s\n' "$LAB_USER" "$LAB_PASS" | chpasswd
chage -I -1 -m 0 -M 99999 -E -1 "$LAB_USER"

# --- 4. SSH password auth ---------------------------------------------------
# sshd keeps the FIRST value it obtains for a keyword, and Include reads
# /etc/ssh/sshd_config.d/*.conf in lexical order. The Ubuntu cloud image ships
# 60-cloudimg-settings.conf with "PasswordAuthentication no", so a 99- drop-in
# is read too late and silently loses. Ours must sort BEFORE the 60- file.
echo "--- enabling password authentication ---"
rm -f /etc/ssh/sshd_config.d/99-bita-lab.conf
cat > /etc/ssh/sshd_config.d/01-bita-lab.conf <<'EOC'
# BITA lab: students connect with a username and password over the VPN.
# Named 01- deliberately: sshd honours the first value it sees for these
# keywords, so this has to be read before 60-cloudimg-settings.conf.
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
UsePAM yes
EOC
chmod 0644 /etc/ssh/sshd_config.d/01-bita-lab.conf

# Belt and braces: disarm the cloud image's directive too, so a future change
# in drop-in ordering cannot lock the whole cohort out again.
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sed -i -E 's/^[[:space:]]*PasswordAuthentication[[:space:]]+no[[:space:]]*$/PasswordAuthentication yes/' \
        /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi

/usr/sbin/sshd -t && { systemctl restart ssh.socket 2>/dev/null; systemctl restart ssh 2>/dev/null; }

# Verify what sshd actually RESOLVED, not what we wrote. Getting this wrong
# ships a lab that nobody can log into, and it fails silently.
if /usr/sbin/sshd -T | grep -qx 'passwordauthentication yes'; then
    echo "OK: sshd resolved passwordauthentication yes"
else
    echo "WARN: sshd did NOT resolve password auth on - students cannot log in"
    /usr/sbin/sshd -T | grep -i passwordauthentication
fi

# --- 5. The nginx lab site (built HEALTHY first) ----------------------------
echo "--- building the port 8081 site ---"
install -d -m 0755 -o root -g root /var/www/lab8081
cat > /var/www/lab8081/index.html <<EOC
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>BITA lab site</title></head>
<body style="font-family:system-ui;background:#0f1115;color:#e6e9ef;padding:3rem">
  <h1>$LAB_MARKER</h1>
  <p>If you can read this from <code>$LAB_HOSTNAME</code>, nginx on port 8081 is fixed.</p>
</body>
</html>
EOC
chown -R www-data:www-data /var/www/lab8081
chmod 0755 /var/www/lab8081
chmod 0644 /var/www/lab8081/index.html

cat > /etc/nginx/sites-available/lab8081 <<'EOC'
server {
    listen 8081 default_server;
    listen [::]:8081 default_server;

    server_name _;
    root /var/www/lab8081;
    index index.html;

    access_log /var/log/nginx/lab8081.access.log;
    error_log  /var/log/nginx/lab8081.error.log warn;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOC
ln -sf /etc/nginx/sites-available/lab8081 /etc/nginx/sites-enabled/lab8081

# Keep the default :80 vhost out of the way so :8081 is the only lab surface.
rm -f /etc/nginx/sites-enabled/default

/usr/sbin/nginx -t && systemctl enable --now nginx && systemctl restart nginx
sleep 2
echo "--- pre-break verification ---"
curl -fsS -m 5 http://127.0.0.1:8081/ | grep -q "$LAB_MARKER" \
    && echo "OK: nginx 8081 healthy before sabotage" \
    || echo "WARN: nginx 8081 NOT healthy before sabotage"

# --- 6. Self-grading health service on :8080 --------------------------------
echo "--- installing the health check service ---"
cat > /etc/systemd/system/bita-health.service <<'EOC'
[Unit]
Description=BITA capstone self-grading health check (http://<instance>:8080)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Runs as root so it can read /etc/shadow to grade the account fault.
User=root
EnvironmentFile=/opt/bita/lab.env
ExecStart=/usr/bin/python3 /opt/bita/health_check.py --serve --port 8080
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOC

cat > /usr/local/bin/bita-check <<'EOC'
#!/bin/sh
# Same grading logic as the web page, in the terminal.
# Needs root: it reads /etc/shadow and /opt/bita/lab.env.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi
set -a
. /opt/bita/lab.env
set +a
exec /usr/bin/python3 /opt/bita/health_check.py --cli "$@"
EOC
chmod 0755 /usr/local/bin/bita-check

systemctl daemon-reload
systemctl enable --now bita-health.service

# --- 6b. Non-critical service baseline (healthy = stopped + disabled) --------
# Installing `at` starts and enables atd by default. The HEALTHY state the
# student is graded against is the opposite: stopped now and disabled at boot.
# break-lab.sh re-arms it (starts + enables) as fault 4.
echo "--- setting non-critical service baseline ($NONCRIT_SERVICE stopped+disabled) ---"
systemctl disable --now "$NONCRIT_SERVICE" 2>/dev/null || true
if systemctl is-active --quiet "$NONCRIT_SERVICE"; then
    echo "WARN: $NONCRIT_SERVICE still active before sabotage"
else
    echo "OK: $NONCRIT_SERVICE stopped and disabled before sabotage"
fi

# --- 7. Break it ------------------------------------------------------------
echo "--- injecting faults ---"
/opt/bita/break-lab.sh

# --- 8. Done ----------------------------------------------------------------
date -Is > /opt/bita/.provisioned
echo "=== bita setup complete: $(date -Is) ==="
