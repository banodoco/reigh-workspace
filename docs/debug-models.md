# Model & Guidance Reference

Reference for debugging model-specific issues. If output looks wrong, check here for parameter compatibility.

---

## Model Internal Names

| UI Name | Internal Name | Guidance System | Max Frames | FPS |
|---------|---------------|-----------------|------------|-----|
| WAN 2.2 | `wan_2_2_i2v_lightning_baseline_2_2_2` | `vace` | 81 | 16 |
| LTX 2.3 Distilled | `ltx2_22B_distilled` | `ltx_control` | 241 | 24 |
| LTX 2.3 Full | `ltx2_22B` | none (unguided) | 241 | 24 |

---

## Guidance Mode → Kind Mapping

| Mode | WAN (vace) | LTX Distilled (ltx_control) |
|------|-----------|----------------------------|
| flow | vace preprocessing | N/A |
| raw | vace (no preprocessing) | N/A |
| canny | vace preprocessing | ltx_control |
| depth | vace preprocessing | ltx_control |
| uni3c | uni3c system | uni3c system |
| pose | N/A | ltx_control |
| video | N/A | ltx_control |

---

## Common Cross-Model Pitfalls

- **WAN phase_config sent to LTX**: Phase configs contain WAN Lightning loras. LTX has `supportsPhaseConfig: false`. Individual segment regeneration must strip `phase_config` for non-phase models.
- **FPS mismatch in join/stitch**: Segment handler generates transitions at a fixed FPS (default 16). Stitch handler must resample downloaded clips to match. FPS is in transition JSON metadata.
- **Resolution mismatch in join/stitch**: Segment handler standardizes clip aspect ratios before generation. Stitch handler must do the same. Resolution is in transition JSON metadata.
