-- ===================================================================
-- VozÍntegra · 004 · Código de acesso por empresa (QR code)
-- Cada empresa ganha um código secreto. O QR code leva para
-- vozintegra.vercel.app/?empresa=<código> e o formulário fica travado
-- nessa empresa. O público deixa de conseguir listar as empresas.
-- Pode ser executado mais de uma vez.
-- ===================================================================

alter table public.empresas add column if not exists codigo_acesso text;

update public.empresas
set codigo_acesso = upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 10))
where codigo_acesso is null;

alter table public.empresas
    alter column codigo_acesso set default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10));

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'empresas_codigo_acesso_key') then
        alter table public.empresas add constraint empresas_codigo_acesso_key unique (codigo_acesso);
    end if;
end $$;

-- O público não lê mais a tabela; só o admin (política "empresas gestao admin").
drop policy if exists "empresas leitura publica" on public.empresas;
revoke select, insert, update, delete, truncate on public.empresas from anon;

-- Busca uma empresa ativa pelo código do QR, sem expor as demais.
create or replace function public.empresa_por_codigo(p_codigo text)
returns table (slug text, nome text)
language sql
stable
security definer
set search_path = public
as $$
    select e.slug::text, e.nome::text
    from public.empresas e
    where e.codigo_acesso = upper(trim(p_codigo))
      and coalesce(e.status, '') <> 'Inativa'
    limit 1;
$$;

revoke all on function public.empresa_por_codigo(text) from public;
grant execute on function public.empresa_por_codigo(text) to anon, authenticated;

-- A política de inserção precisa checar a empresa sem poder ler a tabela.
create or replace function public.empresa_ativa(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.empresas e
        where e.slug = p_slug and coalesce(e.status, '') <> 'Inativa'
    );
$$;

revoke all on function public.empresa_ativa(text) from public;
grant execute on function public.empresa_ativa(text) to anon, authenticated;

drop policy if exists "denuncias insercao publica" on public.denuncias;
create policy "denuncias insercao publica" on public.denuncias
    for insert to anon, authenticated
    with check (
        codigo_consulta ~ '^[A-Z0-9]{8}$'
        and coalesce(total_arquivos, 0) between 0 and 10
        and public.empresa_ativa(empresa_slug)
    );

-- Correção apontada pelo verificador de segurança do Supabase.
alter function public.denuncias_set_updated_at() set search_path = public;
