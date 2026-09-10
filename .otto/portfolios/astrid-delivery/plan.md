# Delivery path

The strongest efficiency move is to protect the in-flight P7 candidate, integrate current-main work once, and let the new managers build on the same accepted composition. Read original project criteria through projects.md and handovers/; use analysis/ only for supporting rationale. This plan adds E2 to the earlier five-program analysis.

## A. Pick up the actual current work

Recover the existing UE manager thread and current P7 CPU handoff: repository SHAs and dirty deltas, remaining closure tasks, accepted session/publication contracts, review counts, required live proof and actual resource balances. Historical files in handovers/unified-execution are the plan contract, not current acceptance. Do not restart P0–P3 or reimplement accepted sessions because an older wrapper failed.

Open the five new manager windows when useful. Their first task is to read their handover, identify dependencies and propose the next exact ready action. They can prepare source maps, tests/fixtures and disjoint changes while P7 finishes; they cannot race the shared closure source.

## B. P7 CPU checkpoint → integration checkpoint

1. The UE manager declares its CPU closure candidate frozen with exact source/evidence and separately lists remaining physical/GPU gates. Pause writers to that candidate, not unrelated work.
2. Compare it with the published current-main/source snapshot per repository. Include relevant tracked and untracked input explicitly; classify already-included, new, conflicting and unrelated work. Capture any late local drift before integration.
3. Create/select one named continuation branch in each affected repository. Keep both input histories and dirty-input manifests recoverable. Reconcile semantics as well as Git conflicts. Do not apply a historical V1 dirty patch if the captured main snapshot already contains it.
4. Validate the combined host/Runtime/client/session/publication and affected user paths. Reuse evidence only where source and inputs still match. A clean merge is not acceptance. Avoid rerunning unrelated broad suites.
5. Publish an exact multi-repository baseline manifest, preserve input refs, and hand the accepted composition to all managers. Record this as the **integration checkpoint**. One coordinating manager directs each shared patch; consumers retain their own acceptance criteria.

Required main inputs needed by P7 itself are integrated under UE's existing process before step 1; the source comparison decides this. The integration checkpoint is behavioral proof and source identity, not an extra model-review panel.

## C. Release work by contracts

- DB owns Runtime schema/verifier/admission and recovery; GEN owns generation/variant publication semantics. Agree GEN's durable/wire requirements while DB designs its exact format. GEN settlement consumes the reviewed DB foundation; full DB completion is not required first.
- UE supplies the existing reviewed session contract and exact code/CPU proof for retained-host consumers. Retrieve these from the current P7 handoff. A one-shot/cloud path that does not consume retained-session changes has no invented GPU wait.
- RRP supplies diagnostics and filename requirements to the corresponding DB/GEN owners. DB replacement/catalog behavior gates actual launcher recovery integration. Keep video opening distinct from V1's ZIP cache while preserving common integrity rules.
- V1 retains V1-01→02→03→04, with 05/06 after 02 and all deterministic gates/real fixture before its bounded UX loop. Do not block it on unrelated GPU acceptance.
- Client generation follows actual versioned contract handoffs. Generate usable clients when consumers need them, then consolidate final parity; never hand-merge generated clients or create an impossible once-ever generation rule.
- E2 owns derived-artifact lifecycle semantics. Agree E2-01 output intent/provenance with GEN and DB before freezing affected schema/publication contracts. DB owns exact schema/admission code; E2 supplies lifecycle requirements and checks. E2-02 precedes adoption (03) and leases/pins/TTL/promotion/deletion (04); E2-05 follows 01/02. E2-06 waits for E2-03/04 and completed V1. A synthetic producer allows E2 foundation work without waiting for visualization. No E2 completion gate is imposed on V1 itself. V1/E2 share one remaining oracle balance. Preserve durable/shared-byte references; prove destructive lifecycle behavior on disposable fixtures before any authorized real operation.

The orchestrator chooses ready tasks, not calendar waves. A task needs its original predecessors, the contracts it actually consumes, available source custody and relevant authorization. If an input changes, invalidate only affected evidence. Detect apparent cycles by separating early contract requirements from later acceptance proof.

## D. Finish and merge

Each manager completes its original criteria and configured reviews on its exact candidate. Integrate continuously at meaningful seams, then run required final affected checks on the chosen combined source. UE physical/warm claims require its actual GPU evidence; a previous fire does not certify new source automatically.

Choose the final executable composition before spending the reserved GPU acceptance allowance, accounting for planned changes to consumed boundaries. Unrelated UX/documentation need not delay that fire; do not spend scarce acceptance attempts on a candidate already known to require relevant changes.

Merge the verified work into each affected repository's main and push normally. Verify remote SHAs and the final cross-repository manifest. Do not force-push or bypass branch protection; use the repository's supported PR path where required. Final update links commits/PRs and evidence, states whether every agreed outcome is met, and stops same-thread wakeup-loop waiting when done or reports a precise unresolved terminal condition.

No new aggregate duration is promised. Prior project estimates were provisional and the user now places UE at P7 CPU closure. Establish remaining scope from that handoff; scheduling is driven by dependencies and actual progress.
