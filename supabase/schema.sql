-- 감사일기 데이터베이스 설정
-- Supabase ▸ SQL Editor ▸ New query 에 전체를 붙여 넣고 [Run] 한 번만 실행하세요.

-- 1) 하루 = 한 줄
create table if not exists public.entries (
  user_id       uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  day           date        not null,                       -- 일기 날짜 (2026-10-28)
  items         text[]      not null default '{}',          -- 감사한 일 목록
  emotion_level smallint    not null default 0
                check (emotion_level between 0 and 7),      -- 1~7, 0 = 기분 미기록
  summary       text,                                       -- 한 줄 총평 (선택)
  updated_at    timestamptz not null default now(),         -- 마지막 저장 시각 (기기에서 기록)
  deleted       boolean     not null default false,         -- 지운 날 (다른 기기에도 삭제 전달)
  primary key (user_id, day)
);

-- 2) 보안: 로그인한 본인의 기록만 읽고 쓸 수 있음 (anon 키가 공개돼도 안전한 이유)
alter table public.entries enable row level security;

drop policy if exists "entries: read own"   on public.entries;
drop policy if exists "entries: insert own" on public.entries;
drop policy if exists "entries: update own" on public.entries;
drop policy if exists "entries: delete own" on public.entries;

create policy "entries: read own"   on public.entries for select using (auth.uid() = user_id);
create policy "entries: insert own" on public.entries for insert with check (auth.uid() = user_id);
create policy "entries: update own" on public.entries for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "entries: delete own" on public.entries for delete using (auth.uid() = user_id);

-- 3) 오래된 내용이 최신 내용을 덮어쓰지 못하게 (나중에 저장한 쪽이 이김)
create or replace function public.entries_keep_newest()
returns trigger language plpgsql as $$
begin
  if new.updated_at < old.updated_at then
    return null;   -- 더 오래된 수정은 무시
  end if;
  return new;
end;
$$;

drop trigger if exists entries_keep_newest on public.entries;
create trigger entries_keep_newest
  before update on public.entries
  for each row execute function public.entries_keep_newest();

-- 4) 실시간 반영 (웹앱이 다른 기기의 변경을 바로 받음)
do $$
begin
  alter publication supabase_realtime add table public.entries;
exception when duplicate_object then null;
end $$;
