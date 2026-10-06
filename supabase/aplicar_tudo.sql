-- VozÍntegra · script único: migrações 000 a 003 na ordem. Cole tudo no SQL Editor do Supabase e clique em Run.
-- Gerado a partir de supabase/migrations/. Pode ser executado mais de uma vez.

-- >>> supabase/migrations/20261006000000_alinhar_esquema.sql
-- ===================================================================
-- VozÍntegra · 000 · Alinhar a tabela denuncias ao formulário atual
-- O banco de produção foi criado com um esquema antigo (descricao, tipo,
-- nome/email/telefone soltos) que não tem as colunas que o index.html
-- grava. Esta migração adiciona as colunas usadas pelo site e remove as
-- políticas permissivas (USING true) que liberavam leitura e escrita a
-- qualquer pessoa. Pode ser executada mais de uma vez.
-- ===================================================================

alter table public.denuncias add column if not exists codigo_consulta    text;
alter table public.denuncias add column if not exists empresa_slug       text;
alter table public.denuncias add column if not exists empresa_nome       text;
alter table public.denuncias add column if not exists tipo_identificacao text;
alter table public.denuncias add column if not exists relato             text;
alter table public.denuncias add column if not exists denunciante        jsonb;
alter table public.denuncias add column if not exists total_arquivos     integer not null default 0;
alter table public.denuncias add column if not exists updated_at         timestamptz default now();

-- Colunas do esquema antigo deixam de ser obrigatórias (o site não as usa).
alter table public.denuncias alter column tipo      drop not null;
alter table public.denuncias alter column descricao drop not null;
alter table public.denuncias alter column status    set default 'Nova';

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'denuncias_codigo_consulta_key') then
        alter table public.denuncias add constraint denuncias_codigo_consulta_key unique (codigo_consulta);
    end if;
end $$;

-- Políticas antigas que davam acesso total ao público.
drop policy if exists "Consultar por protocolo"            on public.denuncias;
drop policy if exists "Qualquer um insere denúncia"        on public.denuncias;
drop policy if exists "Permitir envio e leitura denuncias" on public.denuncias;
drop policy if exists "Permitir empresas"                  on public.empresas;
drop policy if exists "Permitir andamentos"                on public.andamentos;

-- >>> supabase/migrations/20261006000001_rls_e_consulta.sql
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

-- Tabela de andamentos (ainda sem uso no site): só admin.
alter table public.andamentos enable row level security;

drop policy if exists "andamentos gestao admin" on public.andamentos;
create policy "andamentos gestao admin" on public.andamentos
    for all to authenticated
    using (public.is_admin())
    with check (public.is_admin());

revoke all on public.andamentos from anon;

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

-- >>> supabase/migrations/20261006000002_storage_anexos.sql
-- ===================================================================
-- VozÍntegra · 002 · Supabase Storage para anexos das denúncias
-- Requer a migração 001 (função public.is_admin).
-- Bucket privado "anexos": 10 MB por arquivo, PDF, imagens e Word.
-- Caminho dos arquivos: anexos/<id da denúncia>/<arquivo>
-- ===================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'anexos', 'anexos', false, 10485760,
    array[
        'application/pdf',
        'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ]
)
on conflict (id) do update set
    public             = excluded.public,
    file_size_limit    = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Um anexo só é aceito numa pasta de denúncia criada há menos de 1 hora
-- e enquanto não exceder o total de arquivos declarado no registro.
create or replace function public.denuncia_aceita_anexo(p_pasta text)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
    select exists (
        select 1
        from public.denuncias d
        where d.id::text = p_pasta
          and d.created_at > now() - interval '1 hour'
          and (
              select count(*) from storage.objects o
              where o.bucket_id = 'anexos'
                and (storage.foldername(o.name))[1] = p_pasta
          ) < coalesce(d.total_arquivos, 0)
    );
$$;

revoke all on function public.denuncia_aceita_anexo(text) from public;
grant execute on function public.denuncia_aceita_anexo(text) to anon, authenticated;

drop policy if exists "anexos envio publico" on storage.objects;
create policy "anexos envio publico" on storage.objects
    for insert to anon, authenticated
    with check (
        bucket_id = 'anexos'
        and public.denuncia_aceita_anexo((storage.foldername(name))[1])
    );

drop policy if exists "anexos leitura admin" on storage.objects;
create policy "anexos leitura admin" on storage.objects
    for select to authenticated
    using (bucket_id = 'anexos' and public.is_admin());

drop policy if exists "anexos exclusao admin" on storage.objects;
create policy "anexos exclusao admin" on storage.objects
    for delete to authenticated
    using (bucket_id = 'anexos' and public.is_admin());

-- >>> supabase/migrations/20261006000003_empresa_ergohealth.sql
-- ===================================================================
-- VozÍntegra · 003 · ErgoHealth Ltda como empresa do canal
-- Cadastra a ErgoHealth e desativa a empresa de demonstração (Acme).
-- ===================================================================

insert into public.empresas (slug, nome, status)
select 'ergohealth', 'ErgoHealth Ltda', 'Ativa'
where not exists (select 1 from public.empresas where slug = 'ergohealth');

update public.empresas
set nome = 'ErgoHealth Ltda', status = 'Ativa'
where slug = 'ergohealth';

update public.empresas
set status = 'Inativa'
where slug <> 'ergohealth';
