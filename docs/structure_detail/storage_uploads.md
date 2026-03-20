# Storage Uploads (Client-Side)

> **Purpose**: How browser uploads reach Supabase Storage and connect to generations.
> **Source of Truth**: `src/shared/lib/imageUploader.ts`, `src/shared/lib/videoUploader.ts`, `src/shared/lib/storagePaths.ts`

---

## Upload Flow

1. **File selected** in UI (e.g. reference image, shot image, video).
2. **Utility called**: `uploadImageToStorage(file, opts)` or `uploadVideoToStorage(file, projectId, shotId, opts)`.
3. **XHR POST** directly to `{SUPABASE_URL}/storage/v1/object/image_uploads/{path}` with bearer token. NOT the Supabase JS SDK `.upload()` -- uses raw XHR for progress/timeout/abort support.
4. **Public URL** retrieved via `supabase.storage.from('image_uploads').getPublicUrl(path)` and returned.
5. **Caller** writes the URL into DB (generation insert, reference update, etc.) -- uploaders are pure storage utilities.

## Utility Functions

| Function | File | Use |
|----------|------|-----|
| `uploadImageToStorage` | `imageUploader.ts` | Images (60s timeout, 15s stall) |
| `uploadBlobToStorage` | `imageUploader.ts` | Thin wrapper -- converts Blob to File, calls above |
| `uploadVideoToStorage` | `videoUploader.ts` | Videos (5min timeout, 30s stall) |
| `uploadImageWithThumbnail` | `clientThumbnailGenerator.ts` | Uploads image + canvas-generated 300px JPEG thumbnail in parallel |
| `generateAndUploadThumbnail` | `utils/videoThumbnailGenerator.ts` | Extracts video first-frame via canvas, uploads, updates `generations.thumbnail_url` |
| `extractVideoMetadata` | `videoUploader.ts` | Reads duration/dimensions via HTML5 Video API (assumes 30fps) |

## Path Conventions

All paths are built by `storagePaths.*` in `storagePaths.ts`. Single bucket: `image_uploads` (public, listable).

| Builder | Pattern | Example |
|---------|---------|---------|
| `storagePaths.upload` | `{userId}/uploads/{ts}-{rand}.{ext}` | `abc/uploads/1706000000-x3k9m2.png` |
| `storagePaths.thumbnail` | `{userId}/thumbnails/{filename}` | `abc/thumbnails/thumb_1706000000_a1b2c3.jpg` |
| `storagePaths.taskOutput` | `{userId}/tasks/{taskId}/{filename}` | (worker outputs, not client uploads) |

Filenames are `{Date.now()}-{rand8}.{ext}` via `generateUniqueFilename()`. Extension is from filename, MIME fallback, or default (`bin` for images, `mp4` for videos).

## Thumbnail Generation

- **Images**: `generateClientThumbnail` resizes to 300px max dimension via Canvas, outputs JPEG 0.8 quality. Uploaded alongside original by `uploadImageWithThumbnail`. If thumbnail upload fails, original URL used as fallback.
- **Videos**: `useBackgroundThumbnailGenerator` hook finds videos without `thumbnail_url` and queues them. Processes one at a time (2s gap) using canvas frame extraction at t=0.001s. Writes `thumbnail_url` to `generations` table. Max 1280px width, JPEG 0.85 quality.

## Key Invariants

1. **No client-side file validation** beyond `accept` attributes on `<input>`. Size limits enforced server-side (413 response triggers non-retryable error).
2. **Uploads use XHR, not Supabase SDK `.upload()`** -- required for progress callbacks, abort signals, stall detection.
3. **Session refreshed before each retry attempt** -- tokens can expire during exponential backoff (1s, 2s, 4s...).
4. **Uploaders don't write to DB** -- they return a public URL; the caller is responsible for persisting it.
5. **`projectId`/`shotId` params on `uploadVideoToStorage` are vestigial** -- kept for backwards compat, not used in path.
6. **Video thumbnail generator uses `upsert: true`** -- safe to re-run; idempotent per generation ID.

---

[Back to DB & Storage](db_and_storage.md) | [Back to Structure](../../structure.md)
