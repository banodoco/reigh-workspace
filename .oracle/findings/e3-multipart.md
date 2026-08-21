# E3 — Multipart precedent hunt (Astrid-oracle)

## Ranked findings

1. **No multipart parsing exists anywhere.** Only encoder-side builders: `astrid/packs/rendering/executors/sprite_sheet/upscale.py:278,295` (`_multipart_field`/`_multipart_file` build outbound request bodies to providers). Not reusable server-side.
2. **No `cgi` usage** (deprecated 3.11, removed 3.13 — avoid). `email` imports are unrelated: `local_bridge_server.py:11` (`formatdate`), `scripts/reshape/installed_artifact.py:30` (wheel METADATA), tests. `email.parser` would buffer the whole body and is fragile on malformed input — reject.
3. **Bounded-reader precedent:** `astrid/packs/blender/server/blender_render_server.py:63` (`MAX_BODY_BYTES`, env-configurable), `:298-305` (reject bad Content-Length before reading), `:345-349` (`_read_exact` chunked loop). Contrast: bridge JSON body reads are **unbounded** (`local_bridge_server.py:928-955`, `append_service.py:613-615`) — do not copy that shape.
4. **Streaming-copy idiom:** `shutil.copyfileobj(..., length=1024*1024)` — `core/rendering/assets.py:156,336`, `asset_cache.py:264`.
5. **Hashing:** no network-hash helper exists; file-based chunked SHA-256 only — `astrid/core/foundation/hash.py:9` (`sha256_file`, 1 MiB chunks), `core/io/media_import.py:222` (`sha256_file_bytes`). Trivially folded into the receive loop (`digest.update(chunk)` while streaming).
6. **Temp-file/staging discipline (strong):** `astrid/core/foundation/atomic_io.py:36-58` (mkstemp sibling + fsync + `os.replace` + dir fsync); `core/io/media_import.py:506-515` (frozen per-txn quarantine `.astrid/media/.staging/<txn_id>`, staged-byte re-hash before publish, startup GC of unreferenced staging); `_shared/result_manifest.py:311-339` (containment validation).
7. **Python floor / deps:** `requires-python = ">=3.11"` (`pyproject.toml:9`); ruff/mypy target py311 (`:136,176`). **No third-party multipart dep** present (no python-multipart/werkzeug/starlette/requests-toolbelt in deps `pyproject.toml:10-36`).

## Recommendation

**Hand-roll** (~120–180 lines) in the reigh bridge package; reuse repo idioms:

- Validate `Content-Length` up front against a total cap; hard-reject absent length (no chunked transfer-encoding support).
- Single streaming pass over `rfile`: fixed-size chunks into a small rolling buffer; split on `--boundary`; per part, parse headers to first CRLFCRLF.
- Small text fields (fence, task_id, labels) buffered in memory under a strict per-field cap (e.g. 64 KiB–1 MiB); file parts stream to `tempfile.mkstemp` inside the per-txn staging path (`media_import.staging_path`) while updating `hashlib.sha256()` and enforcing a per-file cap; abort ⇒ unlink.
- Enforce max part count; require terminating `--boundary--`; treat truncated body as failure (413/400) with cleanup.
- Publication stays with the existing media-import verify/rename path — parser only produces staged paths + digests.

Loopback single-user threat model: prioritize size-cap correctness over hostile-HTTP hardening; caps make it safe regardless.

Evidence lines verified 2026-08-22 against working tree.
