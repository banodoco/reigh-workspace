> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Plan 1 implementation criteria

- C1: render identity remains `(run, task, video digest, manifest digest)` and wrong bytes fail.
- C2: decoded rendered duration controls coverage; excess tail reaches EOF and is not called black without evidence.
- C3: prompts/unmarked transcripts never enter captions; spoken metadata remains available without shot labels.
- C4: default output is a bounded full-duration overview with mandatory first/last/tail-transition cards and honest selected coverage.
- C5: range, density and resolution are independent recorded values; navigation uses current parser-backed controls.
- C6: structure/render kinds and clocks remain distinct; current CAS/host/cache behavior stays intact.
- UX1: authored-structure questions (tracks/layers/overlap/text/audio/authored timing) use the structure view and evidence, not filmstrip inference.
- UX2: rendered-filmstrip questions use actual viewed frames, decoded full tail, spoken metadata, rendered clock, and exact render identity.
- UX3: cross-view answers preserve the interval, identify both snapshots, and explicitly flag mismatches or unavailable clock mapping; no identical-clock assumption.
- UX4: baseline and two capped Astra UX rounds use fresh Luna actors, frozen images/traces/manifests, deterministic gates, and evidence-based friction assessment; no coaching or hidden truth.
- UX5: image viewing/capture is required for visual-usability claims; missing capability/capture is undetermined, never pass.
