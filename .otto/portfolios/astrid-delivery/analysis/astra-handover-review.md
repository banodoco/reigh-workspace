**Verdict: retain the sequencing design; make the small corrections below before declaring the handover ready.** The package gives a capable same-machine coordinator a workable route through all six projects. I found no unavoidable dependency cycle or need for another scheduler, review panel, or consolidated project.

This was an independent read-only preparation review. I inspected the core documents and prompts, six project handovers, relevant sequencing/acceptance analysis, launcher source, and dependency instructions. I did not spawn agents, modify files, execute product tests, launch projects, publish, or sync. The reported 276 Astrid and 31 Runtime test passes are supplied evidence, not tests I independently reran.

**Required corrections, in priority order**

1. **P1 — Remove the raw operational transcript from the public package.**
   [handovers/ephemeral/shared-decision.md](../handovers/ephemeral/shared-decision.md) contains approximately 3,000 lines of Codex startup metadata, session identity, searches, tool output, and duplicated final text. This directly conflicts with [authority.md’s publication boundary](../authority.md).

   **Small fix:** export the final oracle decision once, retaining its decision ID, source identities, ruling, acceptance requirements, and return conditions. Keep the original transcript locally and record its digest as provenance. Refresh the export digest afterward. Path normalization alone does not turn a raw transcript into suitable public planning material.

2. **P2 — Bind manager launch state to the canonical active control root.**
   [open-manager.py](../scripts/open-manager.py) derives `PACKAGE` from its own location, while `--workspace` independently selects the project roots. Prompts use `PACKAGE`, and launch markers are written beneath it. Following START-HERE’s separate-download route can therefore read live project configuration from one workspace while using stale instructions and duplicate guards from another package checkout. Two downloaded copies also have independent launch markers.

   **Small fix:** resolve the active portfolio root from `--workspace`; use it for manager prompts and local launch state. Alternatively, reject `--execute` when the script’s package root differs from that canonical root. Keep downloaded snapshots as reference inputs. Missing active roots may support readiness inspection, but execution should follow the documented one-time initialization and ownership checks.

3. **P2 — Reconcile the skills revision across the receiving instructions.**
   The newly arrived [dependency README](../dependencies/README.md) specifies published revision `d849898cd0c191cffc5ababbb5ea7d2c188e8ed0` and explains why parent `f129603…` lacks required material. The [receiving prompt](../assets/handover-message.md) still explicitly requires the parent revision.

   **Small fix:** make the published revision the receiving pin everywhere; retain the parent only as historical provenance. Preserve the README’s exact command:

   ```sh
   POMS_SKILLS_SKIP_CLOUD=1 bash "$POMS_DIR/sync.sh"
   ```

   Its instructions correctly distinguish successful sync from skipped, potentially mismatched installed aliases. This finding is a concrete consistency check on the known parallel dependency work, not a recommendation to reopen publication strategy.

4. **P2 — Correct where the receiver obtains consumed counters.**
   The [receiving prompt](../assets/handover-message.md) says to read both ceilings and consumed balances from project `run.yaml`. The inspected configurations declare ceilings; consumption is recorded in status and receipts. GEN’s status, for example, records one oracle call already consumed.

   **Small fix:** replace that sentence with: “Read role bindings and ceilings from the authoritative `run.yaml`; recover consumed counts from active status, receipts, and the current handoff.” Before either V1 or E2 requests an oracle, name the existing central accounting location and serialize charges there. Preserve two remaining calls **across both projects**, independently of V1’s two capped Astra UX invocations.

**Sequencing, acceptance, and operating assessment**

The central sequence is sound: recover the existing UE manager at P7 CPU closure; freeze its candidate; preserve and classify current-main and dirty inputs; reconcile and test one continuation composition; then release overlapping implementation. It preserves accepted earlier work without confusing historical plans with current receipts.

Shared ownership is sufficiently explicit. DB directs Runtime schema/admission/recovery changes, GEN directs publication semantics, and UE retains session ownership. Contributors retain their own acceptance requirements. Early contract exchange avoids the apparent DB/GEN/E2 schema cycle; usable intermediate clients avoid the “generate once” cycle. E2’s synthetic producer permits independent foundation work, while E2-06 follows completed V1 without creating a reverse dependency.

The acceptance distinctions are also strong: CPU fixtures do not establish GPU residency, copied metadata does not establish the original Minkhole bytes, missing image capture is undetermined, and an honest UE terminal does not complete the portfolio. Required reviews and spending limits remain authoritative.

The operating model is proportionate: persistent manager threads, a conservative adjustable worker limit, bounded read-only Luna investigations, and coordinator judgment at checkpoints. Same-thread awaited waiting implements the requested supervision without introducing another scheduler.

**Optional improvement:** add one sentence to [plan.md’s finish instructions](../plan.md) carrying forward the analysis’s final-GPU-budget reservation: choose the final executable composition before spending the reserved acceptance allowance, accounting for planned changes to consumed boundaries. Unrelated UX or documentation need not delay that fire. This makes an existing obligation easier to notice; it adds no review stage.

**Receiver bootstrap facts and preparation closure**

The following remain evidence to recover or verify, rather than reasons to redesign the portfolio:

- Actual UE manager/thread, authoritative root, P7 candidate, accepted contracts, CR2 state, receipts, remaining reviews, and historical live-resource balance.
- Receiving model/delegation access and installed skills identities.
- V1’s actual video fixture and image-capture capability; RRP’s verified historical artifact/access route; GEN’s required live targets and authorized provider allowance.

Exact publication refs and final link validation were explicitly being completed in parallel. I have not treated their temporary absence as a strategic defect. The final preparation pass should reconcile status/publication prose and cover the complete selected package in its checksum manifest. At inspection, all **63 listed export entries** matched their recorded hashes, but that manifest did not cover the core coordinator documents, prompts, launcher, or newly added dependency files.

**Can an intelligent coordinator finish the projects?** Yes—the instructions provide a credible path to implementation, integration, and acceptance after these corrections. Unconditional completion cannot yet be promised: required live proof and remaining allowances are not established by this package. A competent receiver should recover those facts early, continue independent authorized work, and hold only the gates whose mandatory evidence is unavailable.

**Inspected identities and observed changes**

The following core SHA-256 digests were unchanged between initial inspection and the recheck at **2026-09-10 17:24:58 UTC**:

```text
START-HERE.md
953cf0960ecd5203290dab9abbf60bea9128238fe862fc4d85095ee3564a7ba2
authority.md
244e0f37261fe907c7a22fa7b14e5af7281ced7d6182dd0bca36af48a07559c3
agent_goal.md
d45011a89578496a9fb129438ebe1d04ccdeba6f4cf7c6a8cf268fe57bfac185
northstar.md
c7260ec1335efa87ff1fe64d8baca0a3ab1c8e5e8acbe65951626c2a76c45092
plan.md
311934b6a5f0f80b1dd128f9de68784a99379d2a320c861331a40d93a8f1d806
projects.md
a4235f43a067c678ba5d2224b5128303c89355c2c8d145c97b26b00e2ab2df44
operations.md
550002996447e753d2892ed65ce63dd2f9c25457f24167892cad1418004e569d
run.yaml
d149955812d687b597e83a58b1bb794907dc2fa107a2f412842368f015aba216
assets/handover-message.md
28f8888fc5da82e0ae12ad6e7f5abdac36fc1422b77c4d7500d777c0abbb0402
assets/hourly-message.md
b6fb06d914d83b843b4aae4d582b559bd9612efea67099a579ad457ab12b91d5
assets/project-manager-message.md
c2f0b914b6ebecaf3233bf4e1243eb04b556475fdc58434ecf80d47c58d76bc0
```

During review, `dependencies/README.md` appeared and dependency provenance gained the published revision and normalized source paths. I read those updates. Their inspected digests were:

```text
dependencies/README.md
daaed8adacacc8852aad909ac8e9113bd5e41f427b10af318bf22395ce09b41f
dependencies/provenance.json
cb569c17b070ca7e1c94351ac1a978a4ff856bc1494247b9eba206d3f802899a
```

This report reviews those observed document states; it does not certify an immutable, fully published package or any project’s completion.
