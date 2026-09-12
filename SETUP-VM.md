# Local VM Setup — the advanced/special-case path 🐧

**Read this first.** This path is here for two kinds of people:

1. **You need it** — no card for a VPS, workplace or network restrictions, or another concrete reason the cloud paths in [SETUP.md](SETUP.md) won't work for you
2. **You already know this terrain** — you've configured virtual machines before and you're comfortable troubleshooting your own hypervisor

If neither is you, close this tab and take [Path A or Path B](SETUP.md) — not because we doubt you, but because every laptop fails differently here (BIOS settings, chip architecture, hypervisor conflicts, virtual networking), and we'd rather your first week be spent learning Linux than debugging your machine. **The challenge is Linux. Your hypervisor is not the challenge.**

**The 30-minute rule:** if VM setup fights you for more than 30 minutes, stop, switch to [SETUP.md](SETUP.md) Path A or B, and start the lessons. You can always come back to this later in the month — falling behind on Day 1 over a virtualization flag is the worst trade in the whole program.

**Support boundary:** we won't debug VMs on the kickoff call — it's a rabbit hole with an audience. Bring VM issues to **war rooms** or **#kernel-crew**, where someone can sit with you properly. Best effort, no promises: some machine problems are genuinely yours to own on this path.

---

## Before you start — the prereq checklist

- [ ] **RAM:** 8GB+ on your machine (you'll give the VM 2GB and your machine needs to keep breathing)
- [ ] **Disk:** ~25GB free
- [ ] **Virtualization enabled:** Intel VT-x / AMD-V turned on in BIOS/UEFI (most common silent killer on Windows machines — if VMs won't start at all, this is usually why)
- [ ] **Know your chip:** Apple Silicon Macs (M1/M2/M3/M4) can't run VirtualBox properly — use Multipass or UTM instead

---

## Option 1 — Multipass (easiest, Mac/Windows/Linux)

Canonical Ubuntu VMs with one command. If you qualify for this page, start here.

1. Install from [multipass.run](https://multipass.run)
2. In Terminal/PowerShell:
   ```
   multipass launch --name kernelcrew --memory 2G --disk 15G
   multipass shell kernelcrew
   ```
3. You're at an Ubuntu prompt. Run the proof-of-life from [SETUP.md](SETUP.md): `whoami`, `uptime`, `sudo apt update`

Gotchas: on Windows, Multipass needs Hyper-V (Pro) or VirtualBox as a backend (Home); if `multipass launch` hangs, that's the first place to look.

---

## Option 2 — VirtualBox + Ubuntu Server ISO (the classic, Intel/AMD machines only)

More clicks, more control, more ways to wander off the path.

1. Install [VirtualBox](https://www.virtualbox.org) and download the [Ubuntu Server ISO](https://ubuntu.com/download/server)
2. New VM → 2GB RAM, 20GB disk → boot the ISO → accept defaults through the installer — **including "Install OpenSSH server" when offered** (you want the real SSH experience)
3. To SSH in from your own terminal like a real remote server, set the VM's network adapter to **Bridged** (simplest) — or stay on NAT and use the VirtualBox console directly
4. The challenge's own [local server guide](https://linuxupskillchallenge.org/00-Local-Server/) covers this click-by-click, with video

---

## Option 3 — WSL (Windows only, you already know if this is you)

If you live in Windows and already use WSL, it works for the lessons. It's the least "real server" of every option — networking lessons feel different, and some things Just Work in ways that teach you less. Starting fresh? Multipass over WSL.

```
wsl --install -d Ubuntu
```

---

## ✅ Same finish line as everyone else

Once you're at an Ubuntu prompt: run `whoami`, `uptime`, `sudo apt update` clean, **post your screenshot in #kernel-crew**, then head back to [SETUP.md Step 3](SETUP.md#step-3--create-your-challenge-journal-5-min-do-it-on-the-call) to create your challenge journal. From Lesson 1 onward, your path doesn't matter — we're all in the same terminal.
