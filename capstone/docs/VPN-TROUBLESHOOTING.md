# VPN server — build verification and troubleshooting

How to confirm the OpenVPN/NAT host actually came up, and how to find out why
when it did not. Companion to the instructor walkthrough (not published in
this repo), which covers the lab boxes; this file is only about the VPN host
and the tunnel.

Everything here is read-only unless a section says otherwise.

---

## 1. What a normal build looks like

`terraform apply` returns as soon as AWS accepts the instance. **The VPN is not
usable at that point.** The host still has to install OpenVPN before it can
serve, and that install is the whole wait.

Measured on a real build (`cloud-init analyze show`):

```
Finished stage: (init-local)      1.176 s
Finished stage: (init-network)    1.742 s
Finished stage: (modules-config)  0.168 s
Finished stage: (modules-final) 482.476 s
Total Time:                     485.562 s
```

Broken down by module (`cloud-init analyze blame`):

```
481.268s  modules-final/config-package_update_upgrade_install   <-- 99% of the build
  1.282s  init-network/config-ssh
  1.014s  modules-final/config-scripts_user
  0.497s  init-local/search-Ec2Local
  0.109s  init-network/config-bootcmd
  0.097s  modules-config/config-apt_configure
```

**Everything except `apt` costs about 4 seconds.** Expect roughly 3-5 minutes on
a healthy archive; 8 minutes is normal-ish; anything past 15 means something is
wrong upstream, not with this repo.

Boot order, which matters for reading a half-finished build:

| Stage | What runs | Visible effect |
|---|---|---|
| `init-network` | `bootcmd`, `write_files` | Certs and `server.conf` appear **immediately** |
| `modules-config` | `apt_configure` | `ubuntu.sources` rewritten to the chosen mirror |
| `modules-final` | package install, then `runcmd` | OpenVPN installed, then service enabled |

The trap: `/etc/openvpn/server/` is fully populated within seconds of boot, long
before OpenVPN exists. **Seeing the certs there tells you nothing about whether
the VPN works.**

---

## 2. Fast verification

From the repo directory:

```bash
# vpn_endpoint is "IP:PORT/udp", so trim it to the bare address
IP=$(terraform output -raw vpn_endpoint 2>/dev/null | cut -d: -f1)
[ -n "$IP" ] || IP=$(grep '^remote ' generated/bita-capstone.ovpn | awk '{print $2}')
echo "$IP"
```

One command that answers "is it up yet":

```bash
ssh ubuntu@$IP 'systemctl is-active openvpn-server@server; cloud-init status'
```

You want `active` and `status: done`. Any other combination maps to a section below:

| `openvpn` | `cloud-init` | Meaning |
|---|---|---|
| `active` | `done` | Working. Connect. |
| `inactive` | `running` | Still building — normal early on. Go to §4. |
| `inactive` | `done` | **Real failure.** cloud-init finished without starting the VPN. Go to §5. |
| `failed` | any | OpenVPN tried to start and died. Go to §5. |
| (ssh refused) | — | Host not booted, or your IP is outside `admin_ssh_cidrs`. Go to §3. |

Block until the build finishes, then get the timing breakdown:

```bash
ssh ubuntu@$IP 'cloud-init status --wait; sudo cloud-init analyze blame | head -10'
```

Time it end to end from your own machine (handles SSH not being up yet):

```bash
start=$(date +%s)
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      ubuntu@$IP systemctl is-active --quiet openvpn-server@server 2>/dev/null; do
  printf "\r%ds elapsed" $(( $(date +%s) - start )); sleep 10
done
echo " -> VPN ready after $(( $(date +%s) - start ))s"
```

Confirm it is actually listening, and on UDP:

```bash
ssh ubuntu@$IP 'sudo ss -lunp | grep -i openvpn'
# UNCONN 0 0 0.0.0.0:1194 0.0.0.0:* users:(("openvpn",pid=2555,fd=5))
```

> **Do not test the port with `nc -zvu`.** UDP has no handshake, so `nc` reports
> `open` for a dead server, a filtered port, and a working one alike. It produced
> a confident false positive during a real outage. Use `ss` on the host, or just
> connect the client.

---

## 3. Cannot SSH to the host

SSH is gated by `admin_ssh_cidrs` in `terraform.tfvars`, pinned to a single `/32`.
**A changed home IP locks you out of every diagnostic in this document.**

```bash
curl -s https://ifconfig.me; echo          # your current public IP
grep admin_ssh_cidrs terraform.tfvars      # what the SG allows
```

If they differ, update the variable and `terraform apply` — this only modifies
the security group, it does not replace the host.

No SSH and no time to fix it? The EC2 console shows the same cloud-init output:
**Instance → Actions → Monitor and troubleshoot → Get system log.**

Also confirm the break-glass key exists at all: if `admin_ssh_public_key` is
empty, `aws_key_pair.admin` is never created and there is no SSH access by design.

---

## 4. Build is slow or stuck (`inactive` / `running`)

Almost always `apt`. Confirm before assuming:

```bash
ssh ubuntu@$IP 'ps -eo pid,etime,cmd | grep "[a]pt-get"'
```

An `etime` climbing past a couple of minutes on a single `apt-get update` is a
mirror problem, not a busy instance. Cross-check that the box is idle:

```bash
ssh ubuntu@$IP 'uptime'      # load average near 0.0 while apt "works" = waiting on network
```

### Is it the mirror or the network?

This distinction is the whole game. Test a non-Ubuntu destination first:

```bash
ssh ubuntu@$IP '
  curl -4 -o /dev/null -s -w "google      %{http_code} %{time_total}s\n" --max-time 8 http://www.google.com
  for u in http://us-east-1.ec2.archive.ubuntu.com/ubuntu \
           http://security.ubuntu.com/ubuntu \
           http://archive.ubuntu.com/ubuntu \
           http://mirror.math.princeton.edu/pub/ubuntu; do
    curl -4 -o /dev/null -s -w "%{http_code}  $u\n" --max-time 8 "$u/dists/noble/Release"
  done'
```

* **Google 200, mirrors `000`** → upstream Ubuntu archive outage. Nothing in this
  repo will fix it. Wait, or point the templates at a mirror that answers.
* **Everything `000`** → egress problem: check the route table, the SG, and that
  `bootcmd` set up NAT (`sudo iptables -t nat -S POSTROUTING`).
* **Mirrors 200 but apt still crawling** → look for a lock holder:
  `sudo fuser -v /var/lib/dpkg/lock-frontend` and
  `systemctl is-active apt-daily.service unattended-upgrades.service`.

### Which mirror did cloud-init pick?

```bash
ssh ubuntu@$IP 'grep -E "^URIs:" /etc/apt/sources.list.d/ubuntu.sources'
```

Two stanzas: the archive pocket and `noble-security`. Both get rewritten from the
`apt:` block in the template.

> **Known limitation.** cloud-init's `apt.primary.search` is a **DNS-only** check
> — `search_for_mirror()` calls `is_resolvable_url()` and returns the first
> candidate that resolves. It never issues an HTTP request. A mirror that is DNS-
> resolvable but serving nothing still wins the search. During an outage the
> search list therefore behaves exactly like a pin to its first entry. Order the
> list accordingly, and do not assume it is failing over.

Watch it work in real time:

```bash
ssh ubuntu@$IP 'sudo tail -f /var/log/cloud-init-output.log'
```

`Get:` lines are successful fetches, `Ign:` are failures being retried. A healthy
run is nearly all `Get:`. Roughly equal counts means a partially-dead mirror —
slow, but it will usually finish:

```bash
ssh ubuntu@$IP 'sudo grep -c "^Get:" /var/log/cloud-init-output.log;
                sudo grep -c "^Ign:" /var/log/cloud-init-output.log'
```

---

## 5. cloud-init finished but OpenVPN is not running

This is a genuine failure rather than slowness. Work down in this order:

```bash
# 1. Did the package install at all?
ssh ubuntu@$IP 'dpkg -l openvpn | tail -1'

# 2. What does the unit say?
ssh ubuntu@$IP 'systemctl status openvpn-server@server --no-pager -l | tail -20'

# 3. What did the daemon log before dying?
ssh ubuntu@$IP 'sudo tail -40 /var/log/openvpn/openvpn.log'

# 4. Did runcmd even reach the enable step?
ssh ubuntu@$IP 'sudo grep -A5 "runcmd" /var/log/cloud-init.log | tail -20'
```

OpenVPN has **no offline config validator** — `--test-crypto` is for `--secret`
keys and exits 1 with no output even on a perfectly good server config, so do not
use it here. What you can check without starting anything is the PKI on disk:

```bash
ssh ubuntu@$IP '
  cd /etc/openvpn/server
  # cert and key must be a pair - these two hashes have to match
  sudo openssl x509 -in server.crt -noout -modulus | openssl sha256
  sudo openssl rsa  -in server.key -noout -modulus | openssl sha256
  # cert must be signed by the CA the clients carry
  sudo openssl verify -CAfile ca.crt server.crt      # expect: server.crt: OK
  # and be inside its validity window
  sudo openssl x509 -in server.crt -noout -subject -dates'
```

The config itself is only really validated by starting the unit, so the actual
test is `sudo systemctl restart openvpn-server@server` followed by reading
`/var/log/openvpn/openvpn.log` — note this drops any connected students.

Common causes:

| Symptom in `openvpn.log` | Cause |
|---|---|
| `Cannot open ... ca.crt` / `server.key` | `write_files` did not land — check `/etc/openvpn/server/` and permissions (`server.key` must be `0600`) |
| `Options error: --dh` | `dh none` needs OpenVPN 2.4+; check `openvpn --version` |
| `Cannot open /var/log/openvpn/status.log` | `mkdir -p /var/log/openvpn` in `runcmd` did not run |
| `TLS Error: TLS handshake failed` (server side, repeatedly) | Client and server PKI do not match — see §7 |

Manual recovery once mirrors are back (does not require a rebuild):

```bash
ssh ubuntu@$IP
sudo apt-get update && sudo apt-get install -y openvpn
sudo mkdir -p /var/log/openvpn
sudo systemctl enable --now openvpn-server@server
systemctl is-active openvpn-server@server
```

Faster than a destroy/rebuild, and it keeps the EIP and PKI — so every `.ovpn`
already handed out stays valid.

---

## 6. Log map

### VPN host

| Path | Contents |
|---|---|
| `/var/log/cloud-init-output.log` | stdout/stderr of the whole build — apt output lives here |
| `/var/log/cloud-init.log` | cloud-init's own structured log, module by module |
| `/var/log/openvpn/openvpn.log` | daemon log: handshakes, client connects, evictions |
| `/var/log/openvpn/status.log` | current sessions, rewritten periodically |
| `journalctl -u openvpn-server@server` | unit start/stop/restart history |

### Lab boxes (via the tunnel)

| Path | Contents |
|---|---|
| `/var/log/bita-setup.log` | `setup.sh` provisioning: build healthy, verify, then break |
| `/var/log/cloud-init-output.log` | the same, plus everything before `setup.sh` |

### Your machine

The client runs in the foreground and logs to that terminal, **not** to a file.
To keep a record, redirect it:

```bash
sudo openvpn --config generated/bita-capstone.ovpn --log-append /tmp/ovpn-client.log
```

The kernel and NetworkManager still record tunnel transitions regardless:

```bash
journalctl --since "-1h" | grep -iE 'openvpn|tun0'
```

---

## 7. Client will not connect

Confirm the server is up (§2) before touching the client.

**Is a client even running?** It exits silently on some errors:

```bash
ps -C openvpn -o pid,lstart,cmd
ip -br a show tun0            # "does not exist" = not connected
```

**Does the profile match the server?** After a `terraform destroy`, the PKI is
regenerated and the Elastic IP is released — **every previously distributed
`.ovpn` is dead on both counts.** Verify rather than assume:

```bash
# Same CA on both ends?
ssh ubuntu@$IP 'sudo cat /etc/openvpn/server/ca.crt' > /tmp/server-ca.crt
awk '/<ca>/,/<\/ca>/' generated/bita-capstone.ovpn | grep -v '<' | \
  openssl x509 -noout -fingerprint -sha256
openssl x509 -in /tmp/server-ca.crt -noout -fingerprint -sha256
# Fingerprints must be identical.

# Client cert signed by that CA?
awk '/<cert>/,/<\/cert>/' generated/bita-capstone.ovpn | grep -v '<' > /tmp/client.crt
openssl verify -CAfile /tmp/server-ca.crt /tmp/client.crt        # expect: OK

# Pointing at the right host?
grep '^remote ' generated/bita-capstone.ovpn      # e.g. remote 203.0.113.42 1194
terraform output -raw vpn_endpoint               # e.g. 203.0.113.42:1194/udp
```

A mismatch means you are holding a stale profile: re-issue
`generated/bita-capstone.ovpn` to everyone.

**Who is connected right now:**

```bash
ssh ubuntu@$IP 'sudo cat /var/log/openvpn/status.log'
```

---

## 8. Tunnel connects, then drops every few minutes

Not a crash. The client process stays alive the whole time — check `lstart` on
the pid and you will see it never restarted. What flaps is the tunnel.

Signature in the journal, an almost perfectly regular ~231-second cycle:

```
18:07:27 tun0 carrier: link connected
18:11:25 tun0: deleting peer with id 1, reason 2     <- 238s
18:11:27 tun0 carrier: link connected
18:15:18 tun0: deleting peer with id 1, reason 2     <- 231s
```

Confirm on the server:

```bash
ssh ubuntu@$IP 'sudo grep -c "will cause previous active sessions" /var/log/openvpn/openvpn.log'
ssh ubuntu@$IP 'sudo grep -oE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" /var/log/openvpn/openvpn.log | sort | uniq -c | sort -rn'
```

Multiple distinct source IPs plus a non-zero eviction count is the diagnosis:
**two people are sharing one client certificate.** The PKI mints exactly one
client cert (`CN=<project>-student`) and every student gets the same `.ovpn`, so
OpenVPN's default one-session-per-common-name rule makes each new connection
evict the previous one.

The evicted client is not notified — it holds a dead tunnel until `ping-restart`
fires 120s later, reconnects, and evicts the other. Hence ~2 x 120s.

Fix: `duplicate-cn` in `server.conf`, which the template now sets. Verify:

```bash
ssh ubuntu@$IP 'sudo grep -c "^duplicate-cn" /etc/openvpn/server/server.conf'   # expect 1
```

`ifconfig-pool-persist` must stay **absent** alongside it — that file is keyed on
common name, so with a shared CN it hands every client the same address.

---

## 9. Rebuild decisions

Know what each path costs before you run it:

| Action | EIP | PKI / `.ovpn` | Lab boxes |
|---|---|---|---|
| `apply` after a template change | **survives** (re-associates, same address) | **survives** (lives in state) | replaced if their template changed |
| `destroy` + `apply` | **new address** | **regenerated** | rebuilt, new passwords |

So a template fix does **not** require redistributing profiles; a destroy always
does, including a fresh `CONNECTION-DETAILS.txt`.

`terraform destroy` prompts for `instance_count` — **answer 0**. The variable
permits 0 so destroy can be answered; the real "at least one box" rule is a
precondition on `aws_instance.vpn`, which Terraform skips on destroy plans.

### user_data budget

Every byte of `files/` ships inside each instance's user_data, and EC2 caps that
at **16384 bytes in raw (pre-base64) form** — which here means the gzipped
payload, since the templates use `base64gzip()`. Exceeding it fails at **apply**,
not at plan, and with `user_data_replace_on_change = true` that can destroy
instances and then fail to recreate them.

Check the real number before trusting an apply:

```bash
terraform plan -out=/tmp/p.tfplan -var instance_count=2
terraform show -json /tmp/p.tfplan | \
  jq -r '.resource_changes[] | select(.address=="aws_instance.lab[0]") | .change.after.user_data_base64' | \
  base64 -d | wc -c        # compare against 16384
```

The lab boxes are the constrained ones (~88% used). Plain text compresses ~3-4x;
certificates and other high-entropy data barely compress at all.
