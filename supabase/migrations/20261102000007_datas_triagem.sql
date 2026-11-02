-- Datas de triagem e de encerramento, para o relatório gerencial medir os prazos.
--
-- triada_em:    quando a denúncia sai do status "Nova" pela primeira vez.
-- encerrada_em: quando passa para "Concluída" ou "Arquivada" (limpa se reaberta).
-- Valem daqui para frente; denúncias antigas ficam sem essas datas.

alter table public.denuncias add column if not exists triada_em timestamptz;
alter table public.denuncias add column if not exists encerrada_em timestamptz;

create or replace function public.denuncias_marcar_datas()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.status is distinct from old.status then
        if old.status = 'Nova' and new.triada_em is null then
            new.triada_em := now();
        end if;
        if new.status in ('Concluída', 'Arquivada') then
            if new.encerrada_em is null then
                new.encerrada_em := now();
            end if;
        else
            new.encerrada_em := null;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists denuncias_marcar_datas on public.denuncias;
create trigger denuncias_marcar_datas
    before update on public.denuncias
    for each row execute function public.denuncias_marcar_datas();
