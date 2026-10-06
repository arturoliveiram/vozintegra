-- ===================================================================
-- VozÍntegra · 001 · Row Level Security, administradores e consulta
-- Rodar no Supabase: Dashboard > SQL Editor > New query > colar > Run
-- Pode ser executado mais de uma vez sem efeitos colaterais.
-- ===================================================================

-- -------------------------------------------------------------------
-- 1. Administradores (usuários do Supabase Auth com acesso ao painel)
-- -------------------------------------------------------------------
create table if not exists public.admins (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

drop policy if exists "admin ve o proprio registro" on public.admins;
create policy "admin ve o proprio registro" on public.admins
    for select to authenticated
    using (user_id = auth.uid());

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from public.admins where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- -------------------------------------------------------------------
-- 2. Empresas: leitura pública, escrita só admin
-- -------------------------------------------------------------------
alter table public.empresas enable row level security;

drop policy if exists "empresas leitura publica" on public.empresas;
create policy "empresas leitura publica" on public.empresas
    for select to anon, authenticated
    using (true);

drop policy if exists "empresas gestao admin" on public.empresas;
create policy "empresas gestao admin" on public.empresas
    for all to authenticated
    using (public.is_admin())
    with check (public.is_admin());

-- -------------------------------------------------------------------
-- 3. Denúncias
-- -------------------------------------------------------------------
alter table public.denuncias add column if not exists updated_at timestamptz default now();

-- Campos que o denunciante não pode escolher são definidos pelo banco.
create or replace function public.denuncias_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.status     := 'Nova';
    new.created_at := now();
    new.updated_at := now();
    new.codigo_consulta := upper(new.codigo_consulta);
    select e.nome into new.empresa_nome from public.empresas e where e.slug = new.empresa_slug;
    if new.tipo_identificacao is distinct from 'identificado' then
        new.denunciante := null;
    end if;
    return new;
end;
$$;

drop trigger if exists denuncias_before_insert on public.denuncias;
create trigger denuncias_before_insert
    before insert on public.denuncias
    for each row execute function public.denuncias_before_insert();

create or replace function public.denuncias_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists denuncias_set_updated_at on public.denuncias;
create trigger denuncias_set_updated_at
    before update on public.denuncias
    for each row execute function public.denuncias_set_updated_at();

alter table public.denuncias enable row level security;

-- Qualquer pessoa (anon) pode registrar, mas não pode ler, alterar nem apagar.
drop policy if exists "denuncias insercao publica" on public.denuncias;
create policy "denuncias insercao publica" on public.denuncias
    for insert to anon, authenticated
    with check (
        codigo_consulta ~ '^[A-Z0-9]{8}$'
        and coalesce(total_arquivos, 0) between 0 and 10
        and exists (
            select 1 from public.empresas e
            where e.slug = empresa_slug
              and coalesce(e.status, '') <> 'Inativa'
        )
    );

drop policy if exists "denuncias leitura admin" on public.denuncias;
create policy "denuncias leitura admin" on public.denuncias
    for select to authenticated
    using (public.is_admin());

drop policy if exists "denuncias atualizacao admin" on public.denuncias;
create policy "denuncias atualizacao admin" on public.denuncias
    for update to authenticated
    using (public.is_admin())
    with check (public.is_admin());

drop policy if exists "denuncias exclusao admin" on public.denuncias;
create policy "denuncias exclusao admin" on public.denuncias
    for delete to authenticated
    using (public.is_admin());

-- Defesa extra: o papel anônimo nunca lê/altera a tabela diretamente.
revoke select, update, delete, truncate on public.denuncias from anon;

-- -------------------------------------------------------------------
-- 4. Consulta pública pelo código de consulta (sem dados sensíveis)
-- -------------------------------------------------------------------
create or replace function public.consultar_denuncia(p_codigo text)
returns table (
    protocolo      text,
    status         text,
    categoria      text,
    gravidade      text,
    total_arquivos integer,
    created_at     timestamptz,
    updated_at     timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
    select d.protocolo::text, d.status::text, d.categoria::text, d.gravidade::text,
           d.total_arquivos::integer, d.created_at::timestamptz, d.updated_at::timestamptz
    from public.denuncias d
    where d.codigo_consulta = upper(trim(p_codigo))
    limit 1;
$$;

revoke all on function public.consultar_denuncia(text) from public;
grant execute on function public.consultar_denuncia(text) to anon, authenticated;
