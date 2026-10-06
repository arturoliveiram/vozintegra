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
