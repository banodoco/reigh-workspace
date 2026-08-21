# Explore E4: schema-pack manifest constraints for an event-less pack v2

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Shots pack v2 (doc 17, amended) adds tables `generations` + `generation_variants` and a repository — but NO new event stream and NO event kinds (generations are event-less per ratified doc 27). Task: verify in code whether a pack migration/repository can add tables + commands WITHOUT registering new `stream_types`/`event_kinds`/`command_kinds` — read astrid/packs/shots/schema-pack.yaml (all 11 fields), astrid/core/events/registry.py validation rules, astrid/core/migrations/catalog.py ownership rules, astrid/core/conformance/kit.py dimensions (does conformance require hash_chain events per table? does it tolerate event-less tables?), and the m4_gate/composition count assertions (where is the frozen "20 tables" asserted — list exact files+lines that must bump to 22). Also: how does the registry validate that repository commands emit registered events — is an event-less command legal today?

Report ranked findings (<300 words) with file:line evidence; verdict: event-less v2 legal as-is, or minimal manifest/registry change required (specify exactly what).
