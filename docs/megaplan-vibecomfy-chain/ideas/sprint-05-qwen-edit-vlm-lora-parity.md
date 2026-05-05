# Sprint 5: Qwen, Edit-Mode, VLM, and LoRA Preprocessing Parity

## Overall Context

This sprint completes direct image/edit parity and removes WGP-only preprocessing assumptions that would otherwise block orchestrated travel/join/edit-video work.

## Shared Operating Rules

- Do not treat `qwen_image` as equivalent to `qwen_image_2512` unless proven.
- Place Qwen prompt expansion in reigh-worker preprocessing, not template topology.
- Use a LoRA sanitizer and backend-neutral VLM/prompt wrapper with fixture coverage.
- Keep each direct image/edit route WGP-only if its parity is not individually proven.

## Sprint Goal

Finish direct image/edit parity and required preprocessing parity.

## Required Deliverables

- Routes/patches for `qwen_image_2512`, `qwen_image`, `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, and `annotated_image_edit`.
- Prompt-expander preprocess.
- Backend-neutral VLM/prompt-generation wrapper for travel/join/edit-video callers.
- LoRA sanitizer.
- Checked-in `module_names_<arch>.json`.

## Exit Criteria

Direct image/edit routes are green or individually WGP-only; `qwen_image` is validated before use; prompt expansion, VLM prompt fixtures, and LoRA sanitizer pass fixture corpus.

