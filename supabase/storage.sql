-- Storage for inline note images (run once, after schema.sql).
--
-- The bucket is PUBLIC-READ so the Markdown preview can load an image straight
-- from its URL with no auth token. Writes are owner-scoped: an authenticated
-- user may only create/modify/remove objects under their own "<uid>/..."
-- prefix, which the app enforces by keying objects as
-- "<userId>/<noteId>/<uuid>.<ext>".

insert into storage.buckets (id, name, public)
values ('note-images', 'note-images', true)
on conflict (id) do update set public = true;

-- Public read of objects in this bucket.
drop policy if exists "note-images public read" on storage.objects;
create policy "note-images public read"
  on storage.objects for select
  using (bucket_id = 'note-images');

-- Authenticated users may INSERT only under their own "<uid>/..." prefix.
drop policy if exists "note-images owner insert" on storage.objects;
create policy "note-images owner insert"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ...and likewise UPDATE / DELETE only their own objects.
drop policy if exists "note-images owner update" on storage.objects;
create policy "note-images owner update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "note-images owner delete" on storage.objects;
create policy "note-images owner delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'note-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
