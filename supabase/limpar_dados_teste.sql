-- ===================================================================
-- VozÍntegra · OPCIONAL · Apagar os dados de teste do MVP
-- ATENÇÃO: exclusão definitiva. Rode só depois de conferir as linhas
-- com o SELECT abaixo. Não faz parte das migrações automáticas.
-- ===================================================================

-- Conferir antes:
select id, protocolo, empresa_slug, created_at
from public.denuncias
where protocolo in ('DEN-2026-47433', 'DEN-2026-52891', 'DEN-2026-18564')
   or empresa_slug = 'acme-corporation';

-- Apagar:
-- delete from public.denuncias
-- where protocolo in ('DEN-2026-47433', 'DEN-2026-52891', 'DEN-2026-18564')
--    or empresa_slug = 'acme-corporation';
-- delete from public.empresas where slug = 'acme-corporation';
