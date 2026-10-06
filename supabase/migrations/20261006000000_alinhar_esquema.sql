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
