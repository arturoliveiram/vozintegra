-- Aviso por e-mail quando chega uma denúncia nova.
--
-- Quem envia é o próprio banco (pg_net), não o navegador do denunciante:
-- assim nenhum serviço de terceiros recebe o IP de quem denuncia.
-- O e-mail leva só protocolo, empresa, categoria, gravidade e horário.
-- Nunca leva o relato, anexos nem dados de identificação.
--
-- O envio usa o FormSubmit (o mesmo do formulário de proposta) para
-- contato@vozintegra.com.br. Se o envio falhar, a denúncia é gravada
-- normalmente: o aviso nunca impede o registro.

create extension if not exists pg_net with schema extensions;

create or replace function public.avisar_nova_denuncia()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_empresa text;
    v_urgente boolean;
begin
    begin
        select nome into v_empresa from public.empresas where id = new.empresa_id;
        v_empresa := coalesce(v_empresa, new.empresa_nome, 'não informada');
        v_urgente := lower(coalesce(new.gravidade, '')) in ('alta', 'crítica', 'critica');

        perform net.http_post(
            url := 'https://formsubmit.co/ajax/contato@vozintegra.com.br',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Accept', 'application/json',
                'Origin', 'https://www.vozintegra.com.br',
                'Referer', 'https://www.vozintegra.com.br/canal'
            ),
            body := jsonb_build_object(
                '_subject', case when v_urgente then '[URGENTE - triagem em 24h] ' else '' end
                            || 'Nova denúncia ' || coalesce(new.protocolo, ''),
                '_template', 'table',
                '_captcha', 'false',
                'Protocolo', coalesce(new.protocolo, '-'),
                'Empresa', v_empresa,
                'Categoria', coalesce(new.categoria, '-'),
                'Gravidade', coalesce(new.gravidade, '-'),
                'Recebida em', to_char(coalesce(new.created_at, now()) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
                'Prazo de triagem', case when v_urgente then '24 horas' else '3 dias úteis' end,
                'Painel', 'https://www.vozintegra.com.br/gestao',
                'Aviso', 'Por segurança, o relato não vai por e-mail. Leia no painel.'
            )
        );
    exception when others then
        raise warning 'avisar_nova_denuncia falhou: %', sqlerrm;
    end;
    return new;
end;
$$;

revoke all on function public.avisar_nova_denuncia() from public, anon, authenticated;

drop trigger if exists denuncias_aviso_email on public.denuncias;
create trigger denuncias_aviso_email
    after insert on public.denuncias
    for each row execute function public.avisar_nova_denuncia();
