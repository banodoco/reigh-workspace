# Shared V1/E2 oracle decision — final ruling only

Decision source: original render-review-plan-20260910 oracle response, adopted by V1/E2. The final ruling below is exported once, unchanged apart from previously normalized source references. Original transcript remains in the local archive; its original SHA-256 and this export's SHA-256 are retained in closure-manifest.json. Startup metadata, tool output, session identity and duplicated answer are deliberately excluded. This is historical planning authority, not current test or implementation evidence.

**Disposition: approve the simplified integration direction; revise the design before implementation.** V1 should be a normal review-producing capability that publishes an immutable manifest through existing task, receipt, and CAS machinery. No dedicated `review_artifacts` database or review-specific lifecycle service.

Source identity confirmed: workspace HEAD `32910818874b4699281b7ab2b1bd000097ac1c8d`, branch `recovery/runpod-s3-multipart-20260903`. The inspected Astrid code is a nested checkout at `82d09bb91c8a4621695c1d8b6966652cad941ef4`, including dirty changes. This is a planning decision, not an implementation or test-pass claim.

| Issue | Decision and reason | Concrete plan change |
|---|---|---|
| **(a) Six storage classes** | **Collapse them.** Artifact role, retention, pinning, and promotion describe different things. | Separate immutable artifact identity/role from mutable lifecycle policy: durability (`retained` or `regenerable`), retention policy/expiry, and pin references. Promotion creates a normal project-media reference with provenance; it does not change the review artifact’s class or identity. Local materializations remain disposable copies. |
| **(b) Events** | **Reuse generic execution and artifact events.** Overview/range/frame generation are parameterized capability executions, not distinct lifecycle facts. | Delete the proposed review request/generated/failed/pin/GC event family. Use registered generic events and receipt correlation. Opening/navigation is optional telemetry. **V1 needs no new review-domain event** unless it introduces a unique semantic action, such as submitting an editorial decision—which is outside this v1. |
| **(c) Parent lineage** | **Optional for independent requests; mandatory for manifest-derived requests.** Range selection does not inherently imply ancestry. | A stateless request supplies exact render identity and range, with no fabricated parent. Deriving from a manifest requires its digest and review identity, preserves frozen inputs, and rejects conflicting render selectors. Replace “every child names its parent” with this conditional invariant. |
| **(d) Bounded overview** | **Mandatory boundary cards plus adaptive interior.** Guaranteeing every shot boundary defeats a bounded overview. | Reserve cards for the first and last decoded frames and the terminal tail transition, including frames immediately before/at that transition where valid. Deduplicate, then distribute remaining cards across the full duration, prioritizing proven shot boundaries. Record selected frames and sampling limitations. Keep exhaustive boundaries in the index for drill-down. |
| **(e) Authority** | **Manifest/CAS identity is canonical.** A durable-looking path does not establish identity. | Replace the authority claim for `manifest_path` with a managed manifest object ID/digest. Receipts expose that identity and managed entrypoint references; local paths are labelled materializations. Relative member paths are layout information, verified against member digests. |
| **(f) CLI examples** | **Remove speculative commands and flags.** Documentation must describe executable behavior. | Remove proposed `review render`, `timeline view`, and unimplemented preset/resolution examples. Retain only parser-backed examples. Describe pending controls as request semantics; generate actionable commands only when the installed interface supports them. |

The capability contract (original source reference: `<workspace>/Astrid/docs/contracts/capability-artifact-contract.md`) already provides the extension route: a producer declares typed inputs, outputs, and parameters. The generic host (original source reference: `<workspace>/Astrid/astrid/core/execution/generic_host.py:2286`) publishes staged outputs as managed object references. A review extension should use that same route and a shared manifest validator. Adding a second producer must require no producer-specific table, event family, or core dispatch branch.

**Tighten four contracts before proceeding.**

- **Overview versus range:** a default review returns one full-film overview. An independent range request may return only its explicit range and a structured action for obtaining the full overview. It must not claim whole-film coverage or generate a hidden parent. Range, sampling density, and spatial resolution remain independently recorded.
- **Rendered evidence:** use the decoded/probed video clock, with a frame/timestamp mapping when constant FPS cannot be established. The dirty filmstrip implementation (original source reference: `<workspace>/Astrid/astrid/packs/rendering/executors/timeline_visualize/filmstrip_execution.py:17`) probes frame count but computes timing using snapshot FPS. It also infers a black tail from excess duration. Preserve that interval, but call it “unmapped rendered tail” unless pixel evidence establishes blackness.
- **Spoken metadata:** preserve the existing allowlist and frozen-text verification (original source reference: `<workspace>/Astrid/astrid/sdk/timeline_filmstrip.py:35`). Script text remains labelled as script timing, not verified utterance timing. Missing allowed metadata means “no spoken-text metadata,” not proven silence.
- **Lifecycle ownership:** retain existing temporary-workspace cleanup and generic publication mechanisms. The inspected runtime does not demonstrate a reusable pin/TTL/GC API. Name its actual owner or specify the smallest generic extension before claiming reuse. Keep mutable pins/access/expiry outside the immutable manifest. Retained manifest references and evictable derivative references need distinct GC semantics; an evictable derivative is regenerable only while its exact source and recipe remain available.

Avoid a manifest/event digest cycle: the receipt or publication event references the completed manifest digest; the manifest need not embed that publication event’s identity.

**Concrete delivery sequence**

1. Revise the design’s schema, invariants, event mapping, lifecycle ownership, and executable examples together.
2. Deliver one managed render-to-overview journey: exact source identity, rendered clock, permitted captions, manifest publication, verified opening.
3. Add independent range requests and manifest-derived navigation through the same producer contract.
4. Add generic retention/pinning integration and a second extension producer as the extensibility proof. Keep waveform, transcription production, visual-change detection, and offline bundles optional.

**Required acceptance evidence**

- Review render A after render B and timeline edits exist: every output still identifies A; wrong materialized bytes fail verification.
- A render with a long black tail shows its complete duration and final frame; a nonblack excess tail is not mislabelled black. FPS mismatch is handled explicitly.
- Prompts and unmarked transcripts never enter captions; permitted script and verified speech retain their distinct timing provenance.
- A film with hundreds of cuts still produces a bounded, full-duration overview with mandatory cards and honest sampling coverage.
- A stateless range succeeds without a parent; manifest-derived navigation records and verifies ancestry and rejects identity conflicts.
- Cache deletion permits verified rehydration. GC preserves retained/pinned dependencies and active leases; missing regeneration inputs produce an explicit unavailable result.
- Idempotent retries return the original publication/receipt; changed payloads under the same key fail. A second producer uses the same infrastructure without a new database.
- Every documented command parses against the actual interface.

**Return condition:** proceed without another oracle call once the revised plan makes these contracts explicit and identifies the generic lifecycle owner. Return only if an architectural incompatibility prevents them—for example, CAS reachability cannot represent evictable derivatives safely, or generic settlement cannot publish the manifest atomically. Bring the exact conflicting contract and the smallest proposed exception.
