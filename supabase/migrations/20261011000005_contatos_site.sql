-- Pedidos de proposta enviados pelo formulário do site institucional (vozintegra.com.br).
-- Qualquer visitante pode enviar; só administradores leem, alteram ou apagam.
-- Pode ser executado mais de uma vez.

create table if not exists public.contatos_site (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    empresa text,
    nome text not null check (char_length(nome) between 2 and 120),
    email text not null check (char_length(email) between 5 and 160),
    telefone text not null check (char_length(telefone) between 8 and 30),
    colaboradores text check (char_length(colaboradores) <= 30),
    mensagem text check (char_length(mensagem) <= 2000),
    atendido boolean not null default false
);

alter table public.contatos_site enable row level security;

drop policy if exists "contatos insercao publica" on public.contatos_site;
create policy "contatos insercao publica" on public.contatos_site
    for insert to anon, authenticated
    with check (atendido = false);

drop policy if exists "contatos gestao admin" on public.contatos_site;
create policy "contatos gestao admin" on public.contatos_site
    for all to authenticated
    using (public.is_admin())
    with check (public.is_admin());

grant insert on public.contatos_site to anon, authenticated;
grant select, update, delete on public.contatos_site to authenticated;
