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
