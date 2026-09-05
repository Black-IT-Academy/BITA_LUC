# Server Setup Guide — BITA Linux Challenge 🐧

**Goal:** by the end of this page you have a Linux server you can log into, and you've posted your first screenshot in #kernel-crew. That's it. That's Day 0.

We'll do this together live on the **Saturday, Sept 12 kickoff call (12PM ET)** — but if you knock it out early, even better. It's OK if this takes you a minute; the lessons aren't going anywhere.

---

## First: pick your path (30 seconds)

| You | Your path |
|---|---|
| Want the real deal — a server on the actual internet, like the job | **Path A: DigitalOcean** (~$6 total for the month) |
| Want to spend $0 | **Path B: free VM on your own computer** |
| Not sure you're in yet, just want to peek | **Path C: free browser server** (zero setup) |

All three run the same Ubuntu, and the lessons work the same. Path A is what most people who *finish* the challenge use — there's something about a real server with a real IP that makes it real. But a $0 path is a real path. **Pick one and move.** Don't spend Day 0 comparing hosting providers — that's a trap.

> The challenge's own [Day 0 page](https://linuxupskillchallenge.org/00/) has deeper detail on every option, including AWS/Azure if you already have credits there. This guide is the short version.

---

## Path A — DigitalOcean VPS (recommended, ~$6 for the month)

1. **Create an account** at [digitalocean.com](https://www.digitalocean.com) (new accounts usually get free credit — take it)
2. **Create a Droplet** (their word for a server): big green **Create** button → **Droplets**
3. Choose:
   - **Region:** whichever city is closest to you
   - **Image:** **Ubuntu, latest LTS** (24.04)
   - **Size:** cheapest **Basic / Regular** plan ($4–6/mo — the challenge runs fine on the smallest box)
4. **Authentication:** two doors, pick one —
   - **Password** — simplest for today. Make it long and random, save it in a password manager. (The challenge literally teaches you to harden this later — starting simple is fine.)
   - **SSH key** — the pro move, 2 extra minutes. On your machine, open Terminal (Mac) or PowerShell (Windows) and run `ssh-keygen -t ed25519`, press Enter through the prompts, then copy the output of `cat ~/.ssh/id_ed25519.pub` into DigitalOcean's "New SSH Key" box.
5. **Create Droplet** → wait ~60 seconds → copy the **IP address** it shows you
6. **Connect.** Open Terminal (Mac) or PowerShell (Windows — it has ssh built in) and run:
   ```
   ssh root@YOUR.IP.ADDRESS.HERE
   ```
   Type `yes` when it asks about fingerprints (first-connection ritual, totally normal), enter your password if you chose one — and you're standing on your own internet server. 🔥
7. **Prove it's yours.** Run these:
   ```
   whoami
   uptime
   sudo apt update && sudo apt upgrade -y
   ```
8. **💰 Cost control, do this now:** in DigitalOcean → Settings → Billing, add a billing alert at $10. When the challenge ends and you're done with the box, **Destroy** the droplet (not just power off — destroyed = no more charges). ~$6 total, in and out.

**Windows note:** if `ssh` isn't found in PowerShell, install [Windows Terminal](https://aka.ms/terminal) from the Microsoft Store, or use it as your excuse to come to the kickoff call and we'll sort it live.

---

## Path B — Free local VM ($0)

Your computer hosts a little Linux server inside itself. Two good ways:

**Option B1 — Multipass (easiest, Mac/Windows/Linux):**
1. Install from [multipass.run](https://multipass.run)
2. In Terminal/PowerShell:
   ```
   multipass launch --name kernelcrew
   multipass shell kernelcrew
   ```
3. That's it — you're at an Ubuntu prompt. Run the same `whoami` / `uptime` / `sudo apt update` proof-of-life as Path A.

**Option B2 — VirtualBox (the classic, more clicks):**
1. Install [VirtualBox](https://www.virtualbox.org) + download the [Ubuntu Server ISO](https://ubuntu.com/download/server)
2. New VM → 2GB RAM, 20GB disk → boot the ISO → accept defaults through the installer (including "Install OpenSSH server" when offered)
3. LUC's own [local server guide](https://linuxupskillchallenge.org/00-Local-Server/) covers this click-by-click, with a video

**Windows-only Option B3 — WSL:** already comfortable with WSL? It works for the lessons. It's the least "real server" of the options (some networking lessons feel different), so if you're starting fresh, B1 over B3.

---

## Path C — Zero-setup browser server (free, no account drama)

[Killercoda's LUC scenario](https://killercoda.com/linux-upskill-challenge) gives you an Ubuntu server *in your browser*, ready in seconds. Every lesson works except Day 12. The catch: it resets — nothing persists between sessions, and there's no server of *yours* to harden and love. Great for "let me see what this is about," or as a backup when you're away from your machine. If you're in for the full ride, graduate to Path A or B.

---

## ✅ You're ready when…

- [ ] You can log into your server and run `whoami`, `uptime`, and `sudo apt update` without errors
- [ ] **You've posted a screenshot of it in #kernel-crew.** Yes, really. That's your first weekly screenshot, and it tells the coaches you're mission-ready. Boring terminal screenshots are our love language.

---

## Step 3 — Create your challenge journal (5 min, do it on the call)

This is your receipts repo — and later, your ticket into the Firefight.

1. Make a free account at [github.com](https://github.com) (your professional name is a good username — recruiters will see this)
2. Top-right **+** → **New repository** → name it `linux-challenge-journal` → **Public** → check **"Add a README"** → Create
   *(Your own fresh repo — don't fork the BITA repo. You want **your** name and **your** commit history on this one; it's your portfolio, not ours.)*
3. Click the pencil on the README and paste:
   ```
   # My Linux Upskill Challenge Journal
   BITA Kernel Crew · Cohort 1 · Sept 2026

   ## Day 0
   - Set up my server (Path A/B/C) — it's alive 🐧
   - Problems I hit and how I fixed them:
   ```
4. Commit, then **drop your repo link in #kernel-crew**

Every day after a lesson, add a few lines: what you did, anything that broke, how you fixed it. Two minutes a day. By Day 20 it's an interview portfolio you didn't have to "build" — you just kept receipts.

---

## Stuck anywhere on this page?

Say so in **#kernel-crew** — someone's stuck on the same step, guaranteed. Or pull up to a war room, or bring it Saturday. Stuck is not behind. Stuck out loud is literally the program working.
