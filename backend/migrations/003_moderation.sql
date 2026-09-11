-- Rôles de modération. À exécuter après 002_multicity_notifications.sql.
begin;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('moderator', 'admin')),
  created_at timestamptz not null default now()
);
alter table public.user_roles enable row level security;
revoke all on public.user_roles from anon, authenticated;

create or replace function public.is_moderator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role in ('moderator', 'admin')
  );
$$;
revoke all on function public.is_moderator() from public;
grant execute on function public.is_moderator() to authenticated;

drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated using (
  public.is_moderator() or (
    not hidden and not exists (
      select 1 from public.blocks b
      where b.user_id = auth.uid() and b.blocked_user_id = messages.user_id
    )
  )
);
drop policy if exists messages_delete on public.messages;
create policy messages_delete on public.messages for delete to authenticated
using (user_id = auth.uid() or public.is_moderator());
drop policy if exists messages_moderate on public.messages;
create policy messages_moderate on public.messages for update to authenticated
using (public.is_moderator()) with check (public.is_moderator());
grant update(hidden) on public.messages to authenticated;

drop policy if exists reports_read_moderator on public.reports;
create policy reports_read_moderator on public.reports for select to authenticated
using (user_id = auth.uid() or public.is_moderator());
drop policy if exists reports_delete_moderator on public.reports;
create policy reports_delete_moderator on public.reports for delete to authenticated
using (public.is_moderator());
grant delete on public.reports to authenticated;

-- Cette fonction ne peut être appelée que depuis l'éditeur SQL ou avec la clé serveur.
create or replace function public.grant_moderator(account_email text) returns void
language plpgsql security definer set search_path = '' as $$
declare account_id uuid;
begin
  select id into account_id from auth.users where lower(email) = lower(account_email);
  if account_id is null then raise exception 'Aucun compte confirmé trouvé pour cette adresse'; end if;
  insert into public.user_roles(user_id, role) values(account_id, 'moderator')
  on conflict(user_id) do update set role = excluded.role;
end;
$$;
revoke all on function public.grant_moderator(text) from public;

commit;
