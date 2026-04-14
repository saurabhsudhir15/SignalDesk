-- SignalDesk — Supabase Schema
-- Enable pgvector extension
create extension if not exists vector;

-- Sources table
-- Stores raw content from each upload (PDF, YouTube, text)
-- One row per document / video / paste
create table sources (
  id uuid default gen_random_uuid() primary key,
  source_id text unique,       -- filename (PDF) or videoId (YouTube) for dedup
  channel text,                -- influencer / channel name
  input_type text,             -- 'pdf' | 'youtube' | 'text'
  raw_content text,            -- full raw text before extraction
  created_at timestamp default now()
);

-- Signals table
-- Stores extracted investment signals with embeddings
-- One row per stock per document (not one row per document)
create table signals (
  id bigserial primary key,
  content text,                -- formatted signal: stock + stance + verbatim quote + reasoning
  metadata jsonb,              -- stock_name, stance, channel, doc_date, verbatim_quote, reasoning
  embedding vector(1536)       -- OpenAI text-embedding-ada-002
);

-- Semantic search function
-- Used by query_knowledge_tool to retrieve relevant signals
create or replace function public.match_signals (
  query_embedding vector(1536),
  match_count int default null,
  filter jsonb default '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
security definer
as $$
begin
  return query
  select
    signals.id,
    signals.content,
    signals.metadata,
    1 - (signals.embedding <=> query_embedding) as similarity
  from signals
  where signals.metadata @> filter
  order by signals.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- Dashboard function
-- Used by dashboard_tool to return all signals with a doc_date
-- Filtered to last 30 days and grouped by stance in the n8n Code node
create or replace function public.get_current_signals()
returns table (
  stock_name text,
  stance text,
  channel text,
  doc_date text
)
language sql
security definer
as $$
  select
    metadata->>'stock_name',
    metadata->>'stance',
    metadata->>'channel',
    metadata->>'doc_date'
  from public.signals
  where metadata->>'doc_date' is not null;
$$;
