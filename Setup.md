# Server Setup Guide — BITA Linux Challenge 🐧

**Goal:** by the end of this page you have a Linux server you can log into, and you've posted your first screenshot in #kernel-crew. That's it. That's Day 0.

We'll do this together live on the **kickoff call** (Cohort 1: Saturday, Sept 12, 12PM ET) — but if you knock it out early, even better.

---

## The path: keep it simple

| You | Your path |
|---|---|
| Ready to ride (recommended for almost everyone) | **Path A: DigitalOcean** — a real server on the real internet, ~$6 total for the month |
| Spending $0 right now | **Path B: Killercoda** — a free Linux server in your browser, zero install |

That's it. Two doors, both open, both get you to Lesson 1 on Monday. **Pick one and move** — comparing hosting providers on Day 0 is a trap.

> Comfortable running your own virtual machines, or have a specific reason you can't use the cloud? There's a third door for you: **[SETUP-VM.md](SETUP-VM.md)**. If you just read that sentence and thought "what's a hypervisor?" — that door is not for you, and that's by design. Paths A and B exist so your first week is spent learning Linux, not debugging your laptop.

---

## Path A — DigitalOcean VPS (recommended, ~$6 for the month)

There's something about a real server with a real IP address that makes this real. This is the path most people who *finish* the challenge take.

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

**Windows note:** if `ssh` isn't found in PowerShell, install [Windows Terminal](https://aka.ms/terminal) from the Microsoft Store — or bring it to the kickoff call and we'll sort it live.

---

## Path B — Killercoda, free in your browser ($0, zero install)

[Killercoda's Linux Upskill Challenge scenario](https://killercoda.com/linux-upskill-challenge) hands you an Ubuntu server *in your browser tab*, ready in seconds. Nothing to install, nothing to configure, nothing on your machine to break.

Straight talk on the trade-offs:
- ✅ Works for every lesson **except Day 12**
- ✅ Genuinely $0, forever, start in under a minute
- ⚠️ Sessions **reset** — the server doesn't persist between sittings, so you won't have one box you harden and love all month
- ⚠️ For the Firefight capstone you'll connect to a cohort-provided server anyway, so this doesn't block you from graduating

If money's the only thing between you and starting Monday: this is your door, walk through it proudly. You can always graduate to a $6 droplet mid-challenge — several people do exactly that once they're hooked.

---

## ✅ You're ready when…

- [ ] You can log into your server and run `whoami`, `uptime`, and `sudo apt update` without errors *(on Killercoda you're already logged in — just run them)*
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
   - Set up my server (DigitalOcean / Killercoda) — it's alive 🐧
   - Problems I hit and how I fixed them:
   ```
4. Commit, then **drop your repo link in #kernel-crew**

Every day after a lesson, add a few lines: what you did, anything that broke, how you fixed it. Two minutes a day. By Day 20 it's an interview portfolio you didn't have to "build" — you just kept receipts.

---

## Stuck anywhere on this page?

Say so in **#kernel-crew** — someone's stuck on the same step, guaranteed. Or pull up to a war room, or bring it to the kickoff call. Stuck is not behind. Stuck out loud is literally the program working.
