#!/usr/bin/env python3
"""
BITA capstone self-grading health check.

Runs the same four checks the students were asked to fix, live, on every
request. Serves a screenshot-friendly page on :8080 and a JSON view on
/json. Also runs in the terminal via `bita-check`.

The page reports SYMPTOMS ONLY - which checks pass and which fail. Root
causes, file paths and diagnostic commands are deliberately withheld:
working those out is the exercise. Instructors can see the full detail with
`bita-check --evidence` (or `health_check.py --cli --evidence`), which is
never exposed over HTTP.

Standard library only - apt is deliberately broken on this box, so nothing
here may need pip.
"""

import argparse
import datetime
import grp
import html
import http.server
import json
import os
import pwd
import re
import socket
import stat
import subprocess
import sys
import urllib.error
import urllib.request

MARKER = os.environ.get("LAB_MARKER", "BITA-LAB-8081-OK")
LAB_USER = os.environ.get("LAB_USER", "bita-user")
ADMIN_USER = os.environ.get("ADMIN_USER", "bita-admin")
NONCRIT_SERVICE = os.environ.get("NONCRIT_SERVICE", "atd")

NGINX_CONF = "/etc/nginx/nginx.conf"
DOCROOT = "/var/www/lab8081"
SITE_URL = "http://127.0.0.1:8081/"
APT_METHODS_DIR = "/usr/lib/apt/methods"

NOLOGIN_SHELLS = {"/usr/sbin/nologin", "/sbin/nologin", "/bin/false", "/usr/bin/false"}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def run(cmd, timeout=5):
    """Run a command, never raise. Returns (rc, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as exc:  # noqa: BLE001 - the page must never 500
        return 255, "", str(exc)


def octal(path):
    return oct(stat.S_IMODE(os.stat(path).st_mode))[2:].rjust(4, "0")


def owner_of(path):
    st = os.stat(path)
    try:
        user = pwd.getpwuid(st.st_uid).pw_name
    except KeyError:
        user = str(st.st_uid)
    try:
        group = grp.getgrgid(st.st_gid).gr_name
    except KeyError:
        group = str(st.st_gid)
    return user, group


def step(label, ok, evidence):
    return {"label": label, "ok": bool(ok), "evidence": evidence}


def primary_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except Exception:  # noqa: BLE001
        return "unknown"
    finally:
        s.close()


# ---------------------------------------------------------------------------
# check 1 - the locked-out account
# ---------------------------------------------------------------------------

def check_lab_user():
    steps = []

    try:
        entry = pwd.getpwnam(LAB_USER)
    except KeyError:
        steps.append(step("Account exists", False, "no %s entry in /etc/passwd" % LAB_USER))
        return build("account", "%s can log in over SSH" % LAB_USER, steps,
                     goal="The account is unlocked in /etc/shadow and has a real login shell.",
                     diagnostics=account_diagnostics())
    steps.append(step("Account exists", True,
                      "uid=%d shell=%s" % (entry.pw_uid, entry.pw_shell)))

    # /etc/shadow: a leading '!' or '*' on the hash means the account is locked.
    shadow_field = None
    try:
        with open("/etc/shadow", "r", encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split(":")
                if parts and parts[0] == LAB_USER:
                    shadow_field = parts[1] if len(parts) > 1 else ""
                    break
    except PermissionError:
        shadow_field = None
        steps.append(step("Password login is accepted", False,
                          "health check cannot read /etc/shadow (needs root)"))

    if shadow_field is not None:
        locked = shadow_field.startswith("!") or shadow_field.startswith("*")
        has_hash = len(shadow_field.lstrip("!*")) > 10
        preview = (shadow_field[:6] + "...") if shadow_field else "(empty)"
        if locked:
            evidence = "hash field starts with '%s' -> account locked (shadow: %s)" % (
                shadow_field[0], preview)
        elif not has_hash:
            evidence = "no usable password hash set (shadow: %s)" % preview
        else:
            evidence = "hash field is a real hash, no '!' or '*' prefix (shadow: %s)" % preview
        steps.append(step("Password login is accepted", (not locked) and has_hash, evidence))

    shell = entry.pw_shell
    shell_ok = (
        shell not in NOLOGIN_SHELLS
        and os.path.isfile(shell)
        and os.access(shell, os.X_OK)
    )
    if shell in NOLOGIN_SHELLS:
        shell_evidence = "login shell is %s - sshd will refuse the session" % shell
    elif not os.path.isfile(shell):
        shell_evidence = "login shell %s does not exist" % shell
    else:
        shell_evidence = "login shell is %s" % shell
    steps.append(step("Login starts an interactive session", shell_ok, shell_evidence))

    # Expiry / inactivity fields would also lock a user out - report them.
    rc, out, _ = run(["chage", "-l", LAB_USER])
    if rc == 0:
        expired = False
        for line in out.splitlines():
            if line.lower().startswith("account expires") and "never" not in line.lower():
                expired = True
        steps.append(step("Account is currently valid", not expired,
                          "; ".join(l.strip() for l in out.splitlines()
                                    if "expires" in l.lower() or "Password expires" in l)))

    return build("account", "%s can log in over SSH" % LAB_USER, steps,
                 goal="The account is unlocked in /etc/shadow and has a real login shell.",
                 diagnostics=account_diagnostics())


def account_diagnostics():
    return [
        "sudo grep '^%s:' /etc/shadow" % LAB_USER,
        "getent passwd %s" % LAB_USER,
        "sudo passwd -S %s" % LAB_USER,
        "sudo tail -n 40 /var/log/auth.log | grep -i %s" % LAB_USER,
        "sudo journalctl -u ssh --since '-15 min' | tail -n 40",
    ]


# ---------------------------------------------------------------------------
# check 2 - nginx on :8081
# ---------------------------------------------------------------------------

def nginx_conf_user():
    try:
        with open(NGINX_CONF, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        return None, str(exc)
    m = re.search(r"^\s*user\s+([^;\s]+)\s*;", text, re.M)
    if not m:
        return None, "no `user` directive found in %s" % NGINX_CONF
    return m.group(1), None


def check_nginx():
    steps = []

    conf_user, err = nginx_conf_user()
    if conf_user is None:
        steps.append(step("Web server configuration is valid", False, err))
    else:
        try:
            pwd.getpwnam(conf_user)
            exists = True
        except KeyError:
            exists = False
        if not exists:
            evidence = "user directive is '%s' but no such user exists -> nginx: [emerg] getpwnam(\"%s\") failed" % (conf_user, conf_user)
        elif conf_user == "root":
            evidence = "workers would run as root - that is the wrong user for a web server"
        else:
            evidence = "workers run as '%s', which exists" % conf_user
        steps.append(step("Web server configuration is valid",
                          exists and conf_user != "root", evidence))

    rc, out, _ = run(["systemctl", "is-active", "nginx"])
    steps.append(step("Web server is running", out == "active",
                      "systemctl is-active nginx -> %s" % (out or "unknown")))

    # Which user are the workers actually running as right now?
    rc, out, _ = run(["ps", "-o", "user=,comm=", "-C", "nginx"])
    worker_users = sorted({
        line.split()[0] for line in out.splitlines() if line.strip()
    } - {"root"})
    if worker_users:
        evidence = "worker processes owned by: %s" % ", ".join(worker_users)
        ok = conf_user in worker_users if conf_user else True
    else:
        evidence = "no unprivileged nginx worker processes are running"
        ok = False
    steps.append(step("Web server worker processes are up", ok, evidence))

    # Docroot has to be readable/traversable by those workers.
    if os.path.isdir(DOCROOT):
        d_mode = octal(DOCROOT)
        d_owner = "%s:%s" % owner_of(DOCROOT)
        dir_ok = (int(d_mode[-1], 8) & 0o5) == 0o5  # world r+x
        index = os.path.join(DOCROOT, "index.html")
        if os.path.isfile(index):
            f_mode = octal(index)
            f_owner = "%s:%s" % owner_of(index)
            file_ok = (int(f_mode[-1], 8) & 0o4) == 0o4  # world readable
        else:
            f_mode, f_owner, file_ok = "missing", "-", False
        steps.append(step(
            "Web server can read the site content",
            dir_ok and file_ok,
            "%s -> %s %s ; index.html -> %s %s" % (DOCROOT, d_mode, d_owner, f_mode, f_owner),
        ))
    else:
        steps.append(step("Web server can read the site content", False,
                          "%s does not exist" % DOCROOT))

    # The one that actually matters: does the site answer?
    try:
        with urllib.request.urlopen(SITE_URL, timeout=3) as resp:
            body = resp.read(8192).decode("utf-8", "replace")
            code = resp.status
        served = MARKER in body
        evidence = "GET %s -> HTTP %d, marker %s" % (
            SITE_URL, code, "found" if served else "MISSING")
        ok = code == 200 and served
    except urllib.error.HTTPError as exc:
        ok = False
        evidence = "GET %s -> HTTP %d %s" % (SITE_URL, exc.code, exc.reason)
    except Exception as exc:  # noqa: BLE001
        ok = False
        evidence = "GET %s -> %s" % (SITE_URL, exc)
    steps.append(step("Site answers on port 8081 with the lab marker", ok, evidence))

    return build("nginx", "The lab web site is served on port 8081", steps,
                 goal="nginx starts as a real unprivileged user and serves %s on :8081." % MARKER,
                 diagnostics=[
                     "sudo nginx -t",
                     "systemctl status nginx --no-pager -l",
                     "sudo journalctl -u nginx --since '-15 min' --no-pager | tail -n 30",
                     "sudo tail -n 30 /var/log/nginx/error.log /var/log/nginx/lab8081.error.log",
                     "ps -o pid,user,args -C nginx",
                     "ls -ld /var/www/lab8081 && ls -l /var/www/lab8081",
                     "curl -i http://127.0.0.1:8081/",
                 ])


# ---------------------------------------------------------------------------
# check 3 - apt permissions
# ---------------------------------------------------------------------------

def apt_sources_files():
    files = []
    if os.path.isfile("/etc/apt/sources.list") and os.path.getsize("/etc/apt/sources.list") > 0:
        files.append("/etc/apt/sources.list")
    d = "/etc/apt/sources.list.d"
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            if name.endswith((".list", ".sources")):
                p = os.path.join(d, name)
                if os.path.isfile(p):
                    files.append(p)
    return files


def check_apt():
    steps = []

    sources = apt_sources_files()
    if not sources:
        steps.append(step("Package sources are usable", False,
                          "no sources.list / *.sources file found at all"))
    else:
        # Deliberately ONE aggregate step: listing the individual files by
        # name would point straight at the fault.
        details, all_ok = [], True
        for path in sources:
            mode = octal(path)
            user, group = owner_of(path)
            bits = int(mode, 8)
            world_readable = bool(bits & 0o004)
            world_writable = bool(bits & 0o002)
            root_owned = user == "root"
            ok = world_readable and not world_writable and root_owned
            all_ok = all_ok and ok
            if not world_readable:
                why = "not readable by anyone but root - every non-root apt call fails with 'Permission denied'"
            elif world_writable:
                why = "world-writable, which is a privilege-escalation hole"
            elif not root_owned:
                why = "should be owned by root:root"
            else:
                why = "correct"
            details.append("%s: mode %s %s:%s - %s" % (path, mode, user, group, why))
        steps.append(step("Package sources are usable", all_ok, "; ".join(details)))

    # Root ignores read/write bits (CAP_DAC_OVERRIDE) but still needs an
    # execute bit to exec a file - this is the fault that breaks apt for root.
    if os.path.isdir(APT_METHODS_DIR):
        broken = []
        for name in sorted(os.listdir(APT_METHODS_DIR)):
            p = os.path.join(APT_METHODS_DIR, name)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            if not (os.stat(p).st_mode & 0o111):
                broken.append("%s (mode %s)" % (name, octal(p)))
        steps.append(step(
            "Package download transport is usable",
            not broken,
            "all drivers in %s carry an execute bit" % APT_METHODS_DIR if not broken
            else "not executable: %s" % ", ".join(broken),
        ))
    else:
        steps.append(step("Package download transport is usable", False,
                          "%s is missing" % APT_METHODS_DIR))

    return build("apt", "APT can download and install packages", steps,
                 goal="Sources files are root-owned 0644 and every driver in "
                      "/usr/lib/apt/methods is executable.",
                 diagnostics=[
                     "sudo apt-get update",
                     "ls -l /etc/apt/sources.list /etc/apt/sources.list.d/",
                     "ls -l /usr/lib/apt/methods/ | head -n 20",
                     "sudo apt-get -o Debug::Acquire::http=1 update 2>&1 | tail -n 20",
                     "apt-get update --print-uris   # run as a NORMAL user, not root",
                 ])


# ---------------------------------------------------------------------------
# check 4 - a non-critical service that must be stopped AND disabled
# ---------------------------------------------------------------------------

def check_service():
    svc = NONCRIT_SERVICE
    steps = []

    _, active, _ = run(["systemctl", "is-active", svc])
    stopped = active not in ("active", "activating", "reloading")
    steps.append(step("Service is not running", stopped,
                      "systemctl is-active %s -> %s" % (svc, active or "unknown")))

    # is-enabled prints 'enabled' / 'disabled' / 'masked' / 'static' ... on
    # stdout; a stopped-but-still-enabled service would come back at next boot.
    _, enabled, _ = run(["systemctl", "is-enabled", svc])
    not_enabled = enabled in ("disabled", "masked")
    steps.append(step("Service will not start at boot", not_enabled,
                      "systemctl is-enabled %s -> %s" % (svc, enabled or "unknown")))

    return build("service", "The %s service is stopped and disabled" % svc, steps,
                 goal="%s must be stopped now AND disabled so it does not return "
                      "after a reboot." % svc,
                 diagnostics=[
                     "systemctl status %s --no-pager" % svc,
                     "systemctl is-active %s ; systemctl is-enabled %s" % (svc, svc),
                     "sudo systemctl stop %s" % svc,
                     "sudo systemctl disable %s" % svc,
                     "sudo systemctl disable --now %s   # stop + disable in one" % svc,
                 ])


# ---------------------------------------------------------------------------
# assembly
# ---------------------------------------------------------------------------

def build(check_id, title, steps, goal, diagnostics):
    return {
        "id": check_id,
        "title": title,
        "goal": goal,
        "ok": all(s["ok"] for s in steps) and bool(steps),
        "steps": steps,
        "diagnostics": diagnostics,
    }


def public_view(data):
    """Drop everything that would hand the student the answer: per-step
    evidence, the goal statement, and the diagnostic command list. Leaves
    only which checks pass and which fail."""
    out = dict(data)
    out["checks"] = [
        {
            "id": c["id"],
            "title": c["title"],
            "ok": c["ok"],
            "steps": [{"label": s["label"], "ok": s["ok"]} for s in c["steps"]],
        }
        for c in data["checks"]
    ]
    return out


def run_all(include_evidence=False):
    checks = []
    for fn in (check_lab_user, check_nginx, check_apt, check_service):
        try:
            checks.append(fn())
        except Exception as exc:  # noqa: BLE001 - never let a check kill the page
            checks.append({
                "id": fn.__name__, "title": fn.__name__, "goal": "",
                "ok": False,
                "steps": [step("check crashed", False, repr(exc))],
                "diagnostics": [],
            })
    data = {
        "hostname": socket.gethostname(),
        "ip": primary_ip(),
        "generated_at": datetime.datetime.now(datetime.timezone.utc)
                                 .strftime("%Y-%m-%d %H:%M:%S UTC"),
        "passed": sum(1 for c in checks if c["ok"]),
        "total": len(checks),
        "all_ok": all(c["ok"] for c in checks),
        "checks": checks,
    }
    return data if include_evidence else public_view(data)


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

CSS = """
*{box-sizing:border-box}
body{margin:0;background:#0d1117;color:#e6edf3;
     font:15px/1.55 ui-sans-serif,system-ui,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:940px;margin:0 auto;padding:32px 20px 64px}
h1{font-size:22px;margin:0 0 4px;letter-spacing:.2px}
.meta{color:#8b949e;font-size:13px;margin-bottom:22px}
.meta code{color:#c9d1d9;background:#161b22;padding:1px 6px;border-radius:5px}
.banner{border-radius:12px;padding:18px 22px;margin-bottom:26px;
        display:flex;align-items:center;gap:14px;font-weight:650;font-size:19px;
        border:1px solid}
.banner.pass{background:#0b2b18;border-color:#238636;color:#5ce08a}
.banner.fail{background:#2d1116;border-color:#a13b46;color:#ff8a95}
.banner .score{margin-left:auto;font-weight:500;font-size:14px;opacity:.85}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;
      margin-bottom:16px;overflow:hidden}
.card.pass{border-left:4px solid #2ea043}
.card.fail{border-left:4px solid #da3633}
.card h2{font-size:16px;margin:0;padding:14px 18px;display:flex;
         align-items:center;gap:11px;background:#1c2230}
.mark{font-size:19px;line-height:1;width:22px;text-align:center}
.pass .mark{color:#3fb950}
.fail .mark{color:#f85149}
ul{list-style:none;margin:10px 0 0;padding:0 18px 16px}
li{display:flex;gap:11px;padding:7px 0;border-top:1px solid #21262d;align-items:flex-start}
li:first-child{border-top:none}
.lbl{min-width:0;flex:1}
.lbl b{font-weight:600;display:block}
footer{color:#6e7681;font-size:12.5px;margin-top:26px;text-align:center}
"""


def render_html(data):
    def esc(x):
        return html.escape(str(x))

    cards = []
    for c in data["checks"]:
        cls = "pass" if c["ok"] else "fail"
        mark = "&#10004;" if c["ok"] else "&#10008;"
        items = []
        for s in c["steps"]:
            smark = "&#10004;" if s["ok"] else "&#10008;"
            scls = "pass" if s["ok"] else "fail"
            items.append(
                '<li class="%s"><span class="mark">%s</span>'
                '<span class="lbl"><b>%s</b></span></li>'
                % (scls, smark, esc(s["label"]))
            )
        cards.append(
            '<section class="card %s"><h2><span class="mark">%s</span>%s</h2>'
            '<ul>%s</ul></section>'
            % (cls, mark, esc(c["title"]), "".join(items))
        )

    if data["all_ok"]:
        banner = ('<div class="banner pass"><span>&#10004;</span>'
                  '<span>ALL CHECKS PASSED &mdash; screenshot this page</span>'
                  '<span class="score">%d / %d</span></div>' % (data["passed"], data["total"]))
    else:
        banner = ('<div class="banner fail"><span>&#10008;</span>'
                  '<span>Not there yet &mdash; %d of %d checks still failing</span>'
                  '<span class="score">%d / %d</span></div>'
                  % (data["total"] - data["passed"], data["total"],
                     data["passed"], data["total"]))

    return """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>BITA lab health &mdash; %s</title>
<style>%s</style>
</head><body><div class="wrap">
<h1>BITA capstone &mdash; live health check</h1>
<div class="meta">host <code>%s</code> &nbsp; ip <code>%s</code> &nbsp; %s
 &nbsp;&middot;&nbsp; refreshes every 5s &nbsp;&middot;&nbsp; <a href="/json" style="color:#58a6ff">/json</a></div>
%s
%s
<footer>Graded live on every page load. Nothing is cached.<br>
This page reports symptoms only &mdash; working out the cause is the exercise.</footer>
</div></body></html>
""" % (esc(data["hostname"]), CSS, esc(data["hostname"]), esc(data["ip"]),
       esc(data["generated_at"]), banner, "".join(cards))


def render_cli(data, use_colour=True):
    if use_colour and sys.stdout.isatty():
        green, red, dim, reset = "\033[32m", "\033[31m", "\033[2m", "\033[0m"
    else:
        green = red = dim = reset = ""
    lines = [
        "",
        "BITA capstone health check - %s (%s)" % (data["hostname"], data["ip"]),
        data["generated_at"],
        "",
    ]
    for c in data["checks"]:
        colour = green if c["ok"] else red
        lines.append("%s%s %s%s" % (colour, "[PASS]" if c["ok"] else "[FAIL]", c["title"], reset))
        for s in c["steps"]:
            sc = green if s["ok"] else red
            lines.append("   %s%s%s %s" % (sc, "v" if s["ok"] else "x", reset, s["label"]))
            if s.get("evidence"):
                lines.append("      %s%s%s" % (dim, s["evidence"], reset))
        if not c["ok"] and c.get("diagnostics"):
            lines.append("   %sdiagnose with:%s" % (dim, reset))
            for d in c["diagnostics"]:
                lines.append("      %s$ %s%s" % (dim, d, reset))
        lines.append("")
    if data["all_ok"]:
        lines.append("%sALL CHECKS PASSED (%d/%d)%s" % (green, data["passed"], data["total"], reset))
    else:
        lines.append("%s%d of %d checks passing%s"
                     % (red, data["passed"], data["total"], reset))
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# http server
# ---------------------------------------------------------------------------

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "bita-health/1.0"

    def _send(self, code, body, content_type):
        payload = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]
        try:
            data = run_all()
        except Exception as exc:  # noqa: BLE001
            self._send(500, "health check error: %r" % exc, "text/plain; charset=utf-8")
            return

        if path == "/json":
            self._send(200, json.dumps(data, indent=2), "application/json; charset=utf-8")
        elif path == "/healthz":
            self._send(200 if data["all_ok"] else 503,
                       "ok" if data["all_ok"] else "failing",
                       "text/plain; charset=utf-8")
        else:
            self._send(200, render_html(data), "text/html; charset=utf-8")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    ap = argparse.ArgumentParser(description="BITA capstone self-grading health check")
    ap.add_argument("--serve", action="store_true", help="run the web service")
    ap.add_argument("--cli", action="store_true", help="print results to the terminal")
    ap.add_argument("--json", action="store_true", help="print results as JSON")
    ap.add_argument("--evidence", action="store_true",
                    help="INSTRUCTOR view: also print root-cause evidence and "
                         "diagnostic commands. Never served over HTTP.")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--bind", default="0.0.0.0")
    args = ap.parse_args()

    if args.json:
        print(json.dumps(run_all(args.evidence), indent=2))
        return 0
    if args.serve:
        srv = http.server.ThreadingHTTPServer((args.bind, args.port), Handler)
        srv.daemon_threads = True
        sys.stderr.write("bita-health listening on %s:%d\n" % (args.bind, args.port))
        srv.serve_forever()
        return 0

    data = run_all(args.evidence)
    print(render_cli(data))
    return 0 if data["all_ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
