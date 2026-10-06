# Supabase · VozÍntegra

Rode no **SQL Editor** do Supabase, nesta ordem (cada arquivo pode ser executado mais de uma vez):

1. `migrations/20261006000001_rls_e_consulta.sql` ativa RLS, cria a tabela `admins` e a função `consultar_denuncia`.
2. `migrations/20261006000002_storage_anexos.sql` cria o bucket privado `anexos` (10 MB, PDF/imagens/Word) e suas políticas.
3. `migrations/20261006000003_empresa_ergohealth.sql` cadastra a ErgoHealth Ltda e desativa a empresa de demonstração.
4. Opcional: `limpar_dados_teste.sql` apaga as denúncias de teste (confira antes com o SELECT do arquivo).

## Criar um administrador

1. Authentication > Users > Add user > Create new user (e-mail e senha, marque "Auto Confirm User").
2. No SQL Editor:

```sql
insert into public.admins (user_id)
select id from auth.users where email = 'email-do-admin@ergohealth.com.br';
```

3. Recomendado: Authentication > Sign In / Providers > Email, desligar "Allow new users to sign up".

## Quem acessa o quê

| Ação | Público (anon) | Admin logado |
| --- | --- | --- |
| Registrar denúncia | sim | sim |
| Ler/alterar/apagar denúncias | não | sim |
| Consultar andamento | só via `consultar_denuncia(codigo)`: protocolo, status, categoria, gravidade, datas, nº de anexos | sim |
| Enviar anexo | só para uma denúncia criada há menos de 1 hora, até o nº de arquivos declarado | sim |
| Baixar anexo | não | sim (link assinado de 10 min) |
