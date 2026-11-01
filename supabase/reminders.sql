-- 매일 알림 설정 (이미 Supabase에 적용됨 — 기록용)
-- 1) push_subscriptions: 기기별 알림 구독 (로그인한 본인 것만 읽고 쓰기)
-- 2) push_config: 서버 전용 VAPID 키·예약 작업 비밀값 (앱에서 읽을 수 없음)
-- 3) pg_cron 'gratitude-reminders': 매분 Edge Function 'reminders'를 호출해 시간이 된 기기에 알림
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

create table if not exists public.push_subscriptions (
  endpoint     text primary key,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  p256dh       text not null,
  auth         text not null,
  remind_time  time not null default '21:00',
  tz           text not null default 'Asia/Seoul',
  enabled      boolean not null default true,
  last_sent_on date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
-- (정책: read/insert/update/delete own — auth.uid() = user_id)

create table if not exists public.push_config (
  id int primary key default 1 check (id = 1),
  vapid_public text, vapid_private text,
  cron_secret text not null default encode(extensions.gen_random_bytes(24), 'hex')
);
alter table public.push_config enable row level security;

-- select cron.schedule('gratitude-reminders', '* * * * *', $$ select net.http_post(
--   url := 'https://<project>.supabase.co/functions/v1/reminders', body := '{"action":"send"}'::jsonb,
--   headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select cron_secret from public.push_config where id = 1))) $$);
