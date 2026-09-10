# Local source readiness — September 10, 2026

Decision: no additional product-main push is justified by this audit. Preserve the in-flight changes for owner acceptance and the P7 continuation reconciliation; do not sweep dirty checkouts onto main. This is an observation, not a freeze: receiving investigators must refresh source identities before action.

- Astrid: all 44 selected published source paths still byte-match published main `cd4610973f52e3087fd29c282e648e0905b32785`. Additional local gateway dispatch, SDK autobootstrap/client/pagination and corresponding test edits are not covered by that receipt. Existing passing tests do not certify these later deltas.
- Runtime: 13 of the 15 selected paths match source handover `a1ee4343912a47d096d491a752a543986c72e827`. `banodoco_local/runtime_boundary.py` and `runtime_protocol/server.py` changed again; bootstrap and test changes also remain outside the snapshot. The server change serializes HTTP handling under the store mutex and needs owner validation against responsiveness/reliability. The underlying feature branch is nine commits ahead and one behind main: this requires integration, not a blind fast-forward.
- Reigh app: clean at published main `3d3e088653c4b7ff00eca2ecfd9c23859ca0f9f7`; nothing additional to push.
- Reigh worker: clean local `68b701497c4b9363c9d0ab74be1acc0066d71575`, seven commits behind published main `d8fb28875f78bd189dc4046369ee34dcf50e2c1a`, none ahead. Refresh deliberately; there is no unpublished local commit to promote.
- VibeComfy: primary checkout clean at published main `898c4e63cb60a31fe1af9ce5a1fbaa62762d465d`. A separate canonical-workflow worktree contains substantial dirty source/test changes and generated artifacts; recover its owner and accepted composition rather than sweeping it into main.
- Workspace: dirty generated TypeScript registries and recovery-branch history are not a validated portfolio source candidate. Preserve them separately; do not push the entire recovery branch to main.
- Skills: the selected Megado changes are already on the pinned skills handover branch. Unrelated local skill additions are outside this publication.

The coordinator independently verified remote main identities after the read-only audit agents encountered DNS limitations. Detailed local audit reports live under `.otto/reports/portfolio-sequencing-20260910/` in the preparation workspace; they are supporting local evidence, not required portable inputs. Product source publication pins remain in [source-publication.md](source-publication.md).
