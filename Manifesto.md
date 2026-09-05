# Linux Learning Cohorts — Program Manifesto

**Black IT Academy (BITA)** · v1.1 · Cohort 1: **Monday, September 14 → Thursday, October 15, 2026**

> We polled our community on what to learn next. Linux won. This is how we're answering — without building a single lesson.

---

## Why this exists

- **The community asked.** Linux was the #1 result in our member poll.
- **The content already exists.** The world does not need another Linux course. It needs more people who *finish* one. We wrap BITA community around the best free resources instead of building content.
- **It's the foundation.** Linux underpins nearly every path our members are on — cloud, DevOps, security, networking. Prior BITA trainings (AWS, Terraform, Git) all lean on it. This program is the base layer they build from, run on a repeatable cadence.
- **The mission fit.** Free, hands-on, career-relevant skill-building for the Black tech community. No paywalls. No gatekeeping. People pulling each other up.

## What this is (and is not)

This is **not a class series.** Nobody lectures. Missing a day locks nobody out.

This **is a ~30-day challenge with weekly check-ins** — lightly guided, mostly self-guided, accountability through community. The curriculum gives you 20 workdays of lessons (~1–2 hrs each); the cohort gives you 30 calendar days and a reason not to quit on Day 6:

1. **Community** — a cohort channel where everyone is stuck on the same thing you are
2. **Accountability** — short weekly check-ins plus optional co-working "war rooms"
3. **Proof of learning** — discussion-based knowledge checks, because doing a lot of things is not the same as learning a lot of things
4. **Proof of work** — a GitHub repo and a capstone that give every graduate something to talk through in interviews

If someone falls behind, they're not "out" — the format is self-paced, and a new cohort runs on a regular cadence. Nobody is ever far from a fresh start.

## The stack (all free or near-free)

| Layer | Tool | Cost |
|---|---|---|
| Curriculum (the spine) | [Linux Upskill Challenge](https://linuxupskillchallenge.org) — 20 daily lessons, ~1–2 hrs each, server-focused, assumes zero prior knowledge | Free, open source |
| Practice machine | Small cloud VPS (e.g., DigitalOcean) for the real-internet experience, **or** a local VM — both paths documented at kickoff | ~$5–6 for the month · $0 local path |
| Game layer | [OverTheWire Bandit](https://overthewire.org/wargames/bandit/) — command-line wargame over SSH; levels double as a recognition ladder | Free, no account |
| Optional cert prep | Cisco NetAcad **NDG Linux Essentials** for members who want paper (the LPI exam itself is paid — verify current price before promoting it) | Free course |
| Community + recognition | Discord: cohort channel + a dedicated voice channel the whole server can see | Free |
| Proof of work | GitHub: every participant keeps a repo from Day 1 | Free |
| Capstone environment | Cohort-provisioned break-fix servers behind a VPN (see Capstone) | Covered by the program |

> Fundraising note: the VPS is a clean donor ask — roughly **$6 puts a real internet-facing server in a member's hands for the month.**

## The cohort, at a glance

| When | What |
|---|---|
| ~2 weeks out | Interest post in the server; a cohort channel opens as the landing spot |
| Once the group forms | Polls: best check-in days/times + where members are located (time zones), so the schedule fits the majority — not the admins |
| **Sat before Day 1** (Cohort 1: **Sep 12, ~noon ET**) | Intro call: what this is, how to get set up. First-timers get hands-on help creating their first VPS or local VM — extra runway on purpose |
| **Day 1** (Cohort 1: **Mon Sep 14**) | Everybody starts Lesson 1 |
| Weeks 1–4 | Daily lessons self-paced · 1–2 short weekly check-ins (~15 min, standup-style) · 2 optional **war-room** days · one screenshot per person per week |
| Final stretch (through **Oct 15**) | Capstone window — on-demand, when *you're* ready (see Capstone) |
| Grad | Certificates, shoutouts, top-performer recognition, cohort retro (keep/change/drop) |

## The weekly rhythm

- **Check-ins (1–2×/week, ~15 min):** standup-style. Not attendance-taking — a discussion-based knowledge check. Coaches pose real questions from that week's lessons ("what does `ls` tell you, and when would you reach for it?") and talk it through. People who've done this work can tell understanding from activity in minutes; that's the whole assessment engine. Light AI-generated self-quizzes per week-grouping may supplement — they never replace the conversation.
- **War rooms (2×/week, optional):** open voice co-working. No agenda. Sit together, grind your own lessons, throw questions out when stuck, share your screen if you want. Community without obligation.
- **One screenshot a week (everyone):** post one screenshot of something you did or learned that week in the cohort channel. Week 1's will be boring. Post it anyway — seeing where everyone else is *is* the engagement engine. (This came directly from member feedback on a prior BITA training: "I can do this stuff, but I want to learn it alongside people and exchange ideas.")
- **A visible voice channel:** the cohort voice channel is public to the server, so anyone who sees people studying Linux can drop in to help, mentor, or just chop it up — including Linux folks who aren't in the cohort.

## Knowledge map (what "on track" looks like)

The 20 lessons break into weekly groupings, and each check-in covers the grouping behind it. Example: by the end of week 1, you can navigate the filesystem (`pwd`, `ls`, `cd`), edit a file, and pull up a man page — and you can *talk about* what you did, not just paste that you did it. The week-by-week map is published in the cohort channel at kickoff.

Why this matters: the failure mode of self-guided learning is finishing lots of tasks while learning nothing — cruise control. The weekly discussion exists so nobody discovers on Day 20 that they were coasting on copy-paste.

## GitHub from Day 1

Every participant creates their cohort repo at the start and feeds it all month: notes, configs, and — most importantly — **every problem they hit and how they fixed it.** That running log becomes LinkedIn material and interview answers ("tell me about a time you debugged a broken service" — answered, with receipts). It's also the capstone qualifier (below).

## Capstone: the Firefight

The capstone is a **break-fix gauntlet on a real server**, run on demand at the end of the cohort:

1. **Qualify.** You say you're ready — and your cohort repo shows real work in it. No repo, no capstone. (You're only cheating yourself otherwise, and this filters for who's serious.)
2. **Schedule.** Sign up via a simple form; instances are provisioned as people declare ready, not one mass event.
3. **Connect.** You get a VPN profile and credentials. Capstone boxes are **never exposed to the public internet** — an open port 22 gets hammered within minutes, so everything lives behind a VPN with a unique address per instance. Works from Windows or Mac.
4. **Firefight.** Your box has ~4–5 injected, realistic faults — the "reported problems" a junior admin actually inherits: a full disk, broken permissions, a service running as the wrong user, things the logs will reveal if you know where to look. Restore service.
5. **Report.** Write up each issue in your repo — what was broken, how you found it, how you fixed it, screenshots included — readable by a non-expert. **The incident reports are the gold.** Your box lives ~48 hours, then destroys itself.

Infrastructure is code (Terraform-style: "how many instances?" → spin up N identical broken boxes), built and iteratively tested *while* the cohort runs weeks 1–3, so it's battle-tested before the first firefighter connects. **Fallback:** if the environment isn't ready on time, the capstone is the repo + a self-built-server write-up — the program never blocks on the infra.

This is not a proctored exam and BITA is not vouching for anyone's knowledge — there's no certificate authority here. Copying someone's fixes only cheats the copier. Admin effort stays low by design.

## Recognition

- **Graduation:** completion certificate + a wins shoutout that feeds BITA's existing wins pipeline (bulletin, website, socials)
- **Top performers (2–3 per cohort):** a small reward (e.g., gift cards). "Top performer" is defined by **helping others**, repo quality, and visible growth — *not* speed, and not incoming experts cruising familiar ground. The first-time Linux user who grinds, grows, and pulls others up is exactly who this is for.
- **Milestone/Bandit roles:** Discord roles for lesson milestones and OverTheWire Bandit levels, awarded as earned

## Roles (volunteers quit ambiguity, not work)

Named in the cohort kickoff post, every cohort. No unnamed roles, ever.

| Role | Owns | "Done for the week" bar |
|---|---|---|
| **Program Manager** (1) | The cohort as a product: interest drive, guideline docs, grading rubric, schedule polls, grad day, retro, and keeping this document current so *anyone* can run the next one | Roster knows what's happening next; blockers surfaced |
| **Lead Mentor** (1) — *primary owner of check-ins* | Weekly check-ins and knowledge checks; technical hands-on with the cohort | Every check-in happened (or was covered by backup); member questions acknowledged within 24h |
| **Security & Capstone Infra** (1) | The capstone environment: provisioning, VPN, fault-injection, teardown; cross-OS connection testing | Infra work visibly progressed; blockers flagged early, not at capstone time |
| **Mentor coaches** (target 3–4 total) | Coverage — someone is always reachable for questions; cohort self-identified leaders get backup | No question sits unanswered past a day |

**One owner per function, always at least one admin available.** The check-in schedule anchors to the Lead Mentor's availability; other admins overlay for redundancy. **Backup rule:** if a program dies when one person gets busy, it isn't a program — this document is the runbook, and the explicit ambition is that a future cohort could be run entirely by different volunteers.

## What we measure (pilot honesty)

Cohort 1 planning assumption, said out loud: **~30 start, ~20 still moving by week 2, ~10 finish.** That's not failure — that's the honest attrition curve of self-paced learning, and 10 finishers with published firefight reports beats the single-digit completion rates typical of self-paced online courses by miles.

Tracked per cohort: signups → Day-1 starters · week-2 actives · check-in attendance · screenshots posted/week · completion · capstones taken · wins posted. Retro every cohort; the model earns scale by hitting **≥⅓ of starters finishing with a capstone.**

## FAQ

**I've never touched Linux.** Perfect — the challenge assumes zero prior knowledge, and the intro call exists specifically to help you stand up your first server ever.
**I missed some days.** You're fine. It's self-paced; check-ins are for unblocking, not roll call. Catch up, hit a war room, or roll into the next cohort — no penalty, no shame.
**What does it cost?** The course is free. A real VPS runs ~$5–6 for the month; there's a $0 local-VM path if you'd rather.
**Is there a certificate?** BITA issues a completion certificate — and something better: a public repo of real incident reports with your name on it.
**Mac or Windows?** Both. Setup and VPN instructions cover each.
**Can I help even if I'm not in the cohort?** Yes — the voice channel is open. If you know Linux, drop in and mentor. That's the whole model.

## Credits & reuse

The curriculum is the [Linux Upskill Challenge](https://github.com/livialima/linuxupskillchallenge) by livialima and contributors — all credit for the content is theirs. Bandit belongs to [OverTheWire](https://overthewire.org). This document describes the **community wrapper** Black IT Academy runs around those resources, written so any community — or any future BITA volunteer crew — can replicate it. Copy it. That's the point.

*Black IT Academy is a 100% volunteer-led 501(c)(3) nonprofit. blackitacademy.org · givebutter.com/BITA*
