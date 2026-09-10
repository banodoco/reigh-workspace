> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Deterministic UX test-project specification

This is a future delivery fixture specification, not an existing artifact. It is intentionally local, deterministic, no-GPU, and no-cloud. Do not treat this document as proof that a fixture, adapter, actor, or rendered video already exists.

## Fixture contract

Create one synthetic five-minute project with both views authored from the same frozen input:

- Authored structure contains at least two tracks and multiple layers, with deliberate overlaps, text placement, audio placement, authored intervals, and one spoken segment that has no shot label.
- The rendered artifact is an actual decodable video, not a storyboard or list of PNGs. It must contain rapid cuts, a visible terminal excess tail, and a transition whose pixel content is verified before calling it black.
- Include a generation-prompt trap and an unmarked transcript trap. The correct result must exclude both from spoken captions.
- Produce render A and render B from the same project identity but different frozen materialized bytes/manifest identity. The task asks for A after B exists so stale/latest substitution is observable.
- Keep authored clock, rendered decoded clock, and any explicit mapping separate. Never assume shared interval equality; a missing mapping is a reportable condition.
- The fixture builder must publish checksummed manifests and a machine-readable hidden ground truth outside the actor-visible directory. The actor receives only the ordinary brief, public docs/tools, and the actual surfaces it can discover.

## Required UX sequence

1. Baseline: fresh Luna actors attempt authored-structure, rendered-filmstrip, and cross-view briefs.
2. Astra UX round 1: one capped strategic friction/evidence assessment over frozen images, actions, traces, and manifest IDs.
3. Luna-high fix pass 1: implement only precise demonstrated issues; rerun affected deterministic gates.
4. Fresh replay: rerun the affected task from a fresh actor/session and capture the actual images viewed.
5. Astra UX round 2: one capped verification assessment over the affected evidence.
6. Luna-high fix pass 2: implement only accepted precise issues from round 2; rerun affected deterministic gates.
7. Final fresh deterministic/held-out check: fresh Luna actor on the fast-cut/unknown-interval task, with no third hidden Astra critique.

Actual image viewing must be confirmed in evidence. Missing image capability or incomplete capture is `undetermined`, never pass. Deterministic identity, coverage, caption, and parser gates remain blocking; narrative fluency is not visual proof.

## Existing source evidence and missing pieces

Existing source includes `tests/fixtures/timeline_visualize/` (timeline JSON/PNG fixtures, adversarial cases, and compositor-parity inputs), filmstrip unit tests, and Sisypy's evidence-capture/scenario-design guidance. It does not include the required five-minute rendered video, authored dual-view fixture, hidden ground truth package, or an Astrid Sisypy adapter. Delivery must author those pieces in a separately authorized change; this handover copies no arbitrary MP4/cache.

The optional Astrid intro/regression path may be used later as a real-world regression, but it is not a portability dependency and no export is assumed here.
