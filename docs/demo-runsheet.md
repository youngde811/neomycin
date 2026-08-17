# neomycin demo runsheet — "conversational front-end to a symbolic engine"

> **Historical record (pre-v0.9.0).** The belief figures below were produced by the
> per-hypothesis Dempster-Shafer system, which was the default until the shared
> frame of discernment replaced it. They are left as captured rather than rewritten
> — a transcript is a record of what the system did at the time. Current numbers
> differ; see `docs/shared-frame-design.md`.

> **Teleprompter for a ~15-minute live demo.** Audience: software engineers, mixed
> LLM familiarity, health-insurance company. Framing is **non-clinical** — the point
> is the *architecture*: an LLM as a natural-language front-end to a deterministic,
> auditable rules engine. Prompts and expected numbers below were validated in a
> dry-run (Anthropic-direct / sonnet-5); the demo runs on LMS/opus-4-7, same driver
> and system prompt. **Research/teaching tool — NOT FOR CLINICAL USE** (say this once, early).

---

## The one sentence to keep coming back to

> "This happens to diagnose infections, but swap in **claims eligibility** or
> **underwriting** and the architecture is identical: the LLM translates plain English
> into structured facts, a **deterministic rules engine adjudicates and stays the
> auditable system of record**, and when someone asks *'why was this decided?'* the
> answer is the engine's **actual derivation** — not a plausible-sounding guess. The
> LLM never decides. It translates and narrates."

Open with it. Close with it. If you only land one idea, land that one.

---

## Pre-flight (do this before you walk in)

1. **Gateway auth** (LMS/Hyperion): `cvscode auth login` — writes `~/.cvscode/.lms-credentials.json`;
   the driver auto-detects it. (Verify: the file exists.)
2. **Start the bridge** — from an SBCL REPL at the repo root:
   ```lisp
   (load "neomycin.lisp")      ; loads :neomycin, starts the bridge on :8090 (DS default)
   ```
   Sanity check in another shell: `curl -s localhost:8090/health` → `{"status":"ok"}`.
3. **Launch the driver** (leave `rich` on — the markdown tables/bold render beautifully on a projector):
   ```bash
   python src/llm/claude/driver.py
   ```
   You'll get a `Clinician:` prompt. That prompt **is** the demo.
4. Optional: bump terminal font size; a fresh transcript is captured to `./sessions/` automatically.

**If the bridge dies mid-demo:** re-run step 2, then `reset` at the `Clinician:` prompt. Everything is
stateless per case, so you lose nothing.

---

## Timing map (15 min)

| min | beat | you're proving |
|---|---|---|
| 0:00–2:00 | Framing + one architecture slide | LLM = conversational skin; engine = system of record |
| 2:00–7:00 | **Beat 1 — Identify** | NL → symbolic → *graded* conclusion, live |
| 7:00–11:00 | **Beat 2 — "Why?"** (the centerpiece) | the model quotes ground truth; it can't fake the reasoning |
| 11:00–14:00 | **Beat 3 — The contradiction** (kicker) | the engine catches a conflict the LLM alone would gloss |
| 14:00–15:00 | Close on the analogy | — |

**Running long? Cut Beat 3 first** — Beat 2 carries the whole message on its own. Do **not** accept the
model's offer to "run therapy"; just say "not today, thanks."

---

## Beat 0 — Framing (2 min, no typing)

**SAY:** what this is (a 1970s-style symbolic expert system — MYCIN — reconstructed, wrapped so you can
talk to it), and the one sentence above. Show the architecture: **you → LLM → HTTP bridge → Rete rules
engine → belief-valued conclusion → LLM narrates back.** Emphasize: the LLM's job is (a) turn language
into facts, (b) call the engine, (c) explain the engine's answer. It does **not** score anything.

**SAY once:** "This is a teaching reconstruction, not for real clinical use."

---

## Beat 1 — Identify (5 min)

**TYPE (verbatim):**

> A patient with serious burns and a compromised immune system has an aerobic gram-negative rod growing in a 3-day-old blood culture. What organism are we looking at, and how confident should I be?

**WATCH FOR / POINT AT:** the model asserts several **facts** and calls **run inference**, then returns a
two-candidate differential:

- **Pseudomonas — bel 0.76, pl 1.0** (two rules combined)
- **Klebsiella — bel 0.40, pl 1.0** (chained through the enterobacteriaceae *family class*)

**SAY:** "Notice it didn't pick a number — it *asserted facts* and asked the engine. Those beliefs are the
engine's, not the model's. And note `pl 1.0` on both — nothing here argues *against* either candidate yet.
Hold that thought." *(Sets up Beat 3.)*

**SAY (the transferable bit):** "This is the NL-to-symbolic step. In a claims world this is exactly where a
member's free-text situation becomes the structured facts your rules actually run on."

---

## Beat 2 — "Why?" — the centerpiece (4 min)

**TYPE (verbatim):**

> Why pseudomonas — and how sure are you about that 0.76 specifically?

**WATCH FOR / POINT AT:** the model calls **explain_conclusion** and quotes the engine's own derivation —
two independent rules combining:

> *"prior 0.400 combined with the 0.600 rule = 0.760"*

and then the honesty line about the number — near-verbatim from the dry-run:

> *"The sources verify the **association** — Pseudomonas as a leading burn/immunocompromise pathogen — they
> do **not** verify the number 0.76. Those rule weights are **schematic teaching values, not measured
> probabilities.**"*

**SAY — this is your headline:** "That's the whole point. The model is reading **provenance** off the
engine — it *refuses to present a schematic number as a measured one.* For anyone nervous about LLMs in
regulated decisions: it's not improvising the reasoning or the citation. It's quoting an auditable record."

**SAY (transferable):** "Swap 'why 0.76' for 'why was this claim denied' — same move: the explanation is the
engine's actual rule trace, with sources, not a story the model made up after the fact."

---

## Beat 3 — The contradiction — kicker (3 min)

**TYPE (verbatim — note: no culture site, on purpose):**

> New case, start fresh: an aerobic gram-negative rod. The lab reports it ferments lactose, is indole positive, and there's a red pigment on the plate. What is it?

> ⚠️ **Polish note:** don't say "urine culture." The engine only models `blood` as a culture site, so the
> model will (honestly) note it can't assert "urine." Harmless, but it's a distraction — leave the source out.

**WATCH FOR / POINT AT:** two candidates, and — unlike Beat 1 — **both plausibilities drop below 1.0**:

- **E. coli — bel 0.26, pl 0.41** (lactose+/indole+ said E. coli… but the red pigment argues against it)
- **Serratia — bel 0.375, pl 0.625** (red pigment said Serratia… but indole+ argues against it)

The model explains **which finding argued against which organism**, unprompted, and points out E. coli's
plausibility *ceiling* (0.41) is now below Serratia's belief *floor* (0.375).

**SAY:** "Remember `pl 1.0` from Beat 1? Now the reading is internally contradictory — one organism can't be
both — and the engine *says so in its own algebra*: it drops the plausibility on both. It doesn't quietly
average them out. A conflicting input becomes a **visible** widened, lowered interval, and the model can tell
you exactly which finding caused it."

**SAY (transferable):** "That's an engine that knows when its own inputs conflict — the kind of thing you
want surfaced, not smoothed over, in any adjudication system."

---

## Beat 4 — Close (1 min)

Repeat the one sentence. Land it: **the LLM makes the engine conversational and explainable; the engine
keeps the LLM honest.** Neither half does the other's job. Offer to take questions; the transcript of the
whole session was saved to `./sessions/` if anyone wants to see the raw tool calls.

---

## Cheat sheet — expected numbers (confirm on screen)

| Beat | Organism | bel | pl |
|---|---|---|---|
| 1 | pseudomonas | 0.76 | 1.0 |
| 1 | klebsiella | 0.40 | 1.0 |
| 2 | *(pseudomonas derivation)* | `0.400 + 0.600 rule = 0.760` | — |
| 3 | e-coli | 0.26 | **0.41** |
| 3 | serratia | 0.375 | **0.625** |

## Likely audience questions (quick answers)

- **"Is the LLM doing the reasoning?"** No. It translates language to facts and narrates the engine's
  output. The scoring is 100% the deterministic Rete engine.
- **"Where do the numbers come from?"** Schematic teaching values (the model will tell you this itself). The
  *architecture* is the point; grounding some of those numbers in real frequency data is on the roadmap.
- **"What's Dempster-Shafer / why intervals?"** Belief `[bel, pl]`: a lower bound (committed evidence) and an
  upper bound (1 − evidence against). `pl` below 1.0 means something argued against the hypothesis — that's
  the Beat 3 effect. You can also run it in classic certainty-factor mode for contrast.
- **"Could this hallucinate a diagnosis?"** It can only report what the engine concluded; if it tried to
  invent one, there'd be no matching fact in working memory. That's the guardrail the architecture buys you.