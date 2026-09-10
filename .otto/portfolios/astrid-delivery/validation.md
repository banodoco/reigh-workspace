# Validation and limits

## Completed preparation checks

- Focused source tests: **276 Astrid passed in 18.14s; 31 Runtime passed in 1.61s**. Exact commands, scope and audited dirty patch identities are in [source-validation.md](analysis/source-validation.md). The first Runtime collection failure was corrected by setting PYTHONPATH=.; no product fix was made.
- Independently verified all **44 Astrid and 15 Runtime published path/blob pairs** against their commits and queried both remote refs for exact equality.
- A real fresh GitHub clone of the skills handover branch resolved to `d849898cd0c191cffc5ababbb5ea7d2c188e8ed0`. Its Megado skill, sync script and wake helper matched the inspected exports. Both shell scripts pass bash syntax checks. No real installed/global/cloud sync was run; the recipient must perform the documented local-only sync and inspect skipped aliases.
- In a fresh package copy outside the workspace: every Markdown file link resolved; all YAML parsed; launcher Python parsed; all five new-project launch commands passed dry-run; executing the downloaded-copy launcher against the existing workspace was rejected with exit 2 before any launch/state write; wakeup-loop --sleep 0 returned its completion marker and exit 0.
- The custom hourly watcher is absent. No project window, product execution, deployment or paid resource was started.
- One independent actual Astra high read-only critique completed; all four required findings were addressed. [Review/dispositions](review.md) distinguishes the original reviewed hashes from subsequent checked corrections.
- Public export inspection removed the raw E2 operational transcript, retaining its final decision once and the original digest. Credential/private-path/transcript-marker scans were applied to the selected package, not unrelated local trees. Marker scans are not guarantees that arbitrary secrets are detectable.
- The complete selected publication file set is covered by [closure-manifest.json](closure-manifest.json), except the manifest itself to avoid recursive hashing. Original snapshot hashes remain alongside final export hashes; authored coordinator files and added dependencies are also included.

Approved multi-repository follow-up: verified the five product-repository remote URLs from the local checkouts; all portable links and YAML/Python syntax checked; all **six** new-manager choices (including integration) passed dry-run in a fresh copy. A foreign-copy integration launch was rejected before state mutation. No manager or product test was launched. The earlier Astra review is not represented as reviewing these later edits; the separately requested focused Astra assessment is preserved in analysis/parallelism-and-final-integration-astra.md. Final publication regenerates the full manifest and checks the actual committed archive.

## What this does not establish

The focused tests ran on audited dirty inputs and support source preservation. They do not prove the P7 closure, the six projects, the combined continuation composition, GPU residency, live provider cleanup, production readiness or excluded repositories. Later active-worktree drift is outside those receipts. Source publication and review are not deployment permission.

Receiving bootstrap must recover the actual UE manager/source/CR2 and live/review balances; verify current model/delegation access, the real V1 fixture/image capture and any required historical artifact/provider access. Do not fabricate these or restart earlier phases because a wrapper is stale.

At P7 freeze source, reconcile published main and relevant late local inputs in the agreed continuation custody, run affected integration checks and release only ready dependents. Final completion requires every original mandatory criterion/review and compatible tested source on verified remote main. Missing mandatory live proof remains a real limitation, not a reason to mark the product complete.
