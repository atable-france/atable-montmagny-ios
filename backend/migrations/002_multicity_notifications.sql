-- Multi-ville et centre de notifications. À exécuter après backend/schema.sql.
alter table public.messages add column if not exists city_slug text not null default 'montmagny';
create index if not exists messages_city_topic_date on public.messages(city_slug, topic, created_at desc);

create table if not exists public.city_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  city_slug text not null,
  notify_comments boolean not null default true,
  notify_messages boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(user_id, city_slug)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  message_id uuid references public.messages(id) on delete cascade,
  city_slug text not null,
  title text not null check(char_length(title) between 1 and 120),
  body text not null check(char_length(body) between 1 and 240),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_date on public.notifications(user_id, created_at desc);

alter table public.city_subscriptions enable row level security;
alter table public.notifications enable row level security;

drop policy if exists subscriptions_own on public.city_subscriptions;
create policy subscriptions_own on public.city_subscriptions for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists notifications_read_own on public.notifications;
create policy notifications_read_own on public.notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications for delete to authenticated using(user_id=auth.uid());

revoke all on public.city_subscriptions, public.notifications from anon, authenticated;
grant select, insert, update, delete on public.city_subscriptions to authenticated;
grant select, update(read_at), delete on public.notifications to authenticated;
grant insert(user_id, city_slug, topic, body) on public.messages to authenticated;

create or replace function public.notify_new_message() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications(user_id, actor_id, message_id, city_slug, title, body)
  select s.user_id, new.user_id, new.id, new.city_slug,
    case when new.topic like 'menu:%' then 'Nouveau commentaire sur un menu' else 'Nouveau message entre parents' end,
    left(new.body, 240)
  from public.city_subscriptions s
  where s.city_slug = new.city_slug
    and s.user_id <> new.user_id
    and case when new.topic like 'menu:%' then s.notify_comments else s.notify_messages end;
  return new;
end;
$$;
revoke all on function public.notify_new_message() from public;
drop trigger if exists notify_message_after_insert on public.messages;
create trigger notify_message_after_insert after insert on public.messages for each row execute function public.notify_new_message();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
