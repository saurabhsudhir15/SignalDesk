# SignalDesk

**Your portfolio's memory for influencer signals.**

> Know exactly where every holding stands, without spending hours catching up.

Capstone project | Mahesh Yadav Agentic AI PM Course | Cohort 8 | Saurabh Sudhir

**[Watch the demo](https://drive.google.com/file/d/1KPNofX7zokVpXbP6dQ0KZuj_Q9qLJXF0/view?usp=sharing)**

---

## What It Does

SignalDesk is a Telegram-native agentic AI system that captures investment signals from financial influencer content, tracks how their thesis on each stock evolves over time, and lets you query your entire signal history in plain language.

You send a YouTube link, a PDF, or paste a post. Thirty seconds later, the signal is in your library with the verbatim quote, the reasoning, and the date. You never had to watch the video to know what it said.

---

## The Problem

India has 200 million demat accounts, up 5x since 2019. Financial influencers on YouTube alone have 20 million+ followers, and SEBI began regulating finfluencers in 2023 precisely because their influence on retail investment behaviour was undeniable.

Active retail investors follow 3 to 5 trusted influencers across YouTube paid memberships, Instagram posts, and community screenshots. Signals from these influencers are the investment strategy, not a side activity.

The workflow breaks in three concrete ways:

1. **Engagement gaps are inevitable.** Life constraints mean investors go 4 to 8 weeks without engaging with content. When they return, they see price movement in their holdings but cannot recall the current influencer stance. Result: paralysis. No action taken on stocks they already had signals for.

2. **Thesis evolution is invisible.** An influencer says "Hold" in December, "Trim on resistance" in January, "Sold 60%" in February across three different formats. There is no system tracking this arc. Every catch-up is done manually from scratch.

3. **The cost is real.** Investors miss positions in stocks they already had conviction on. Not because the signal was missing, because the workflow broke before they could act.

---

## Why Agentic AI, Not Rules or Generic AI

**Rule-based systems fail here because:**
- Input is unstructured and multimodal: signals arrive as 18-page narrative PDFs, Instagram screenshots, and YouTube videos. Rules cannot extract "HDFC Bank: trim 60% on next rally" from flowing prose.
- Thesis evolution requires contextual reasoning: "start trimming on resistance" in January must be understood as an update to the December "hold" stance on the same stock, not a duplicate entry.
- Catch-up requires batch reasoning: after a 2-month gap, the agent must process multiple documents in sequence, understand which updates supersede earlier ones, and surface only what changed.

**Generic AI (Claude Projects, NotebookLM) falls short because:**
- No push delivery. The core problem is that investors stop engaging when life gets busy. Claude Projects requires opening a tab and asking a question. SignalDesk delivers to Telegram without requiring any initiation.
- No thesis timeline. Claude Projects has no notion of a temporal arc across documents and no structured entity tracking per stock.
- No workflow fit. Telegram is the investor's existing communication environment. Zero new habit required.

---

## How It Works

```
User sends PDF / YouTube URL / pasted text via Telegram
        |
        v
Switch node routes by input type (PDF / YouTube / text)
        |
        v
Dedup check (source already in knowledge base?)
        |
        v
GPT-4o-mini extracts signals: ticker + stance + verbatim quote + reasoning
        |
        v
Content check: is this investment-related? injection detected?
        |
        v
Signals stored in Supabase with pgvector embeddings (one row per stock)
        |
        v
Telegram reply: signals found, formatted with source + date
        |
        v
On any plain-text query: Orchestrator agent routes to
  - store_signal_tool (new content)
  - query_knowledge_tool (semantic search across all stored signals)
  - dashboard_tool (all current signals grouped by stance)
```

**What you see per holding:**

```
HDFC Bank
Influencer A: Hold (Dec PDF) -> Trim on resistance (Jan post) -> Sold 60% (Feb post)
Last update: 12 days ago
Verbatim: "I've started trimming HDFC on every rally..."
```

**Signal recency tiers applied at query time:**

| Tier | Age | Behaviour |
|---|---|---|
| Current | 0 to 30 days | Actionable. Shown first. |
| Sector | 31 to 90 days | Industry context. Shown after Current. |
| Historical | 91 to 180 days | Stance changes and cycle narrative. |
| Archive | 180+ days | Not surfaced unless explicitly requested. |

---

## Tech Stack

| Layer | Tool |
|---|---|
| Orchestration | n8n (self-hosted) |
| Interface | Telegram Bot API |
| Extraction LLM | GPT-4o-mini (temp 0.1) |
| Orchestrator LLM | GPT-4o-mini (temp 0.2) |
| Vector store | Supabase with pgvector |
| YouTube transcripts | Supadata API |
| Memory | Window Buffer Memory (n8n) |

---

## Architecture

### Main Workflow

![SignalDesk Main Flow Part 1](images/SignalDesk%20main%20flow%20part%201.png)

![SignalDesk Main Flow Part 2](images/SignalDesk%20main%20flow%20part%202.png)

### Extract Signal from Text

![Extract Signal from Text](images/SignalDesk%20Extract%20signal%20from%20text%20post.png)

### Dashboard

![Dashboard](images/SignalDesk%20-%20Stock%20dashboard.png)

Three n8n workflows:

**Main workflow** handles all Telegram input. Routes PDF, YouTube URL, and plain text through separate paths. Each path runs dedup, extraction, content check, Supabase insert, and Telegram reply.

**Store Signal sub-workflow** handles text path content storage. Called by the orchestrator agent via tool use when new influencer commentary is pasted.

**Dashboard sub-workflow** calls a Supabase RPC (`get_current_signals`) and returns all stocks with signals in the last 30 days, grouped by stance.

The orchestrator uses three tools: `store_signal_tool`, `query_knowledge_tool`, and `dashboard_tool`. Tool selection is decided by the agent based on message intent, not hardcoded routing.

Key design decisions:
- Precision over recall: extraction prompt instructs GPT-4o-mini to only extract what is directly stated, never infer
- Injection hardening: unified extraction prompt includes a security block that treats embedded instructions as plain text, not commands
- SEBI compliance by design: the system surfaces and organises what influencers said, never generates recommendations. Every signal is paired with a verbatim quote so the user sees exactly what was said before acting
- Dedup on both paths: source_id (filename for PDF, videoId for YouTube) checked before any processing
- Split Stocks node: emits one Supabase row per stock (and per sector), not one row per document

---

## Database Schema

Two Supabase tables. Full schema in [`docs/schema.sql`](docs/schema.sql).

**sources** — one row per upload (PDF, YouTube video, pasted text)

| Column | Type | Notes |
|---|---|---|
| source_id | text (unique) | filename for PDF, videoId for YouTube — used for dedup |
| channel | text | influencer / channel name |
| input_type | text | pdf, youtube, or text |
| raw_content | text | full raw text before extraction |
| created_at | timestamp | auto-set on insert |

**signals** — one row per stock per document

| Column | Type | Notes |
|---|---|---|
| content | text | formatted signal for embedding |
| metadata | jsonb | stock_name, stance, channel, doc_date, verbatim_quote, reasoning |
| embedding | vector(1536) | OpenAI text-embedding-ada-002 |

Two Supabase functions: `match_signals` (semantic search via pgvector cosine similarity) and `get_current_signals` (returns all signals with a doc_date for the dashboard).

---

## Evaluation

Golden set: 9 test cases across real finfluencer PDFs and YouTube videos, with 98 to 99 ground truth signals manually annotated. Full tracker in [`docs/SignalDesk_Eval_Tracker.xlsx`](docs/SignalDesk_Eval_Tracker.xlsx).

| Metric | Result | Target |
|---|---|---|
| Precision | 97% | 95%+ |
| Safety (no advice-drift language) | 100% | 100% |
| Recall | 59% | 60%+ |

**Why precision was prioritised over recall:** A false positive (hallucinated signal) could lead to a wrong investment decision. A missed signal is a gap the user can fill by asking a follow-up question. The product surfaces every signal alongside its verbatim source quote so the user always sees exactly what the influencer said before acting.

---

## What Makes It Hard to Copy

Three layers:

1. **Persistent signal history.** The longer you use SignalDesk, the more irreplaceable your library becomes. A temporal knowledge graph of every influencer's evolving position on every stock you follow is not something anyone can replicate by pasting a link into ChatGPT.

2. **Attribution infrastructure.** Every signal has a verbatim quote, a source, and a date. Users do not act on summaries in a financial context. They act on proof. That trust layer is engineered, not assumed.

3. **Evaluation discipline.** 97% precision at Alpha with a documented precision-recall tradeoff is not a prompt someone wrote in 20 minutes. Prompt injection defence is also built in: the extraction pipeline rejects content that attempts to manipulate it.

---

## What I Would Build Next

**Alpha 2:** Then vs now diff. After each new upload, surface what changed since the last signal for any stock already in the library. "Influencer was Hold in December. Now: Trim on resistance."

**V1:** Proactive monitoring. SignalDesk watches the channels, you do not have to send anything. Solves the engagement gap at the source.

**V2:** Conviction tracking. When a creator changes their view on something already in your library, you get an alert without asking.

**V3:** Leaderboard + backward simulation. "If you had followed this influencer's advice for the last year, what would a portfolio look like now?" Builds trust through historical validation and creates a natural path to cross-influencer signal synthesis.

---

## Built By

Saurabh Sudhir | Senior Product Manager | Mahesh Yadav Agentic AI PM Course, Cohort 8
