-- À exécuter dans un projet Supabase dédié. Aucune clé service_role dans l'application.
begin;
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 40)
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic text not null check (topic in ('general','menus','ideas') or topic ~ '^menu:[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  hidden boolean not null default false
);
create index messages_topic_date on public.messages(topic, created_at desc);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now(),
  unique(message_id,user_id)
);
create table public.blocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  primary key(user_id,blocked_user_id), check(user_id<>blocked_user_id)
);
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

create function public.on_parent_created() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,nickname) values(new.id,case when char_length(trim(new.raw_user_meta_data->>'nickname')) between 2 and 40 then trim(new.raw_user_meta_data->>'nickname') else 'Parent' end);
  return new;
end; $$;
create trigger parent_created after insert on auth.users for each row execute function public.on_parent_created();
revoke all on function public.on_parent_created() from public;

create policy profiles_read on public.profiles for select to authenticated using(true);
create policy blocks_read on public.blocks for select to authenticated using(user_id=auth.uid());
create policy blocks_insert on public.blocks for insert to authenticated with check(user_id=auth.uid());
create policy blocks_delete on public.blocks for delete to authenticated using(user_id=auth.uid());
create policy messages_read on public.messages for select to authenticated using (
  not hidden and not exists(select 1 from public.blocks b where b.user_id=auth.uid() and b.blocked_user_id=messages.user_id)
);
create policy messages_insert on public.messages for insert to authenticated with check(user_id=auth.uid() and not hidden);
create policy messages_delete on public.messages for delete to authenticated using(user_id=auth.uid());
create policy reports_insert on public.reports for insert to authenticated with check(user_id=auth.uid());
create policy reports_read_own on public.reports for select to authenticated using(user_id=auth.uid());

revoke all on public.profiles,public.messages,public.reports,public.blocks from anon;
revoke all on public.profiles,public.messages,public.reports,public.blocks from authenticated;
grant select on public.profiles to authenticated;
grant select,delete on public.messages to authenticated;
grant insert(user_id,topic,body) on public.messages to authenticated;
grant select on public.reports to authenticated;
grant insert(message_id,user_id,reason) on public.reports to authenticated;
grant select,insert,delete on public.blocks to authenticated;

create function public.limit_message_rate() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
  if (select count(*) from public.messages where user_id=new.user_id and created_at>now()-interval '1 minute') >= 5 then
    raise exception 'Veuillez patienter avant de publier un nouveau message.';
  end if;
  return new;
end; $$;
create trigger message_rate before insert on public.messages for each row execute function public.limit_message_rate();
revoke all on function public.limit_message_rate() from public;

create function public.delete_my_account() returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentification nécessaire'; end if;
  delete from auth.users where id=auth.uid();
end; $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
-- Puis exécuter backend/migrations/002_multicity_notifications.sql.
commit;
