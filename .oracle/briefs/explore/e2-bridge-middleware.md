# Explore E2: bridge middleware surface (where the local-trust gate hooks)

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

In `astrid/core/integrations/reigh/local_bridge_server.py`: map the exact request lifecycle — `parse_request` (:189–193?), `handle_one_request` (:178–186?), dispatch if/elif chain, body reading (`_read_request_body`), and the diagnostics wraps. Answer precisely: (1) can a gate see and validate headers (Host, custom header, token) BEFORE the request body is consumed? (2) where exactly would a per-boot-token + Host + custom-header rejection hook go with minimal surface? (3) how does the server bind (interface/port) and where would 0700 data-dir enforcement live at serve boot (`astrid serve` composition root)? (4) existing CORS/_ALLOWED_HEADERS mechanics (:242–263).

Report ranked findings (<300 words) with file:line evidence and the minimal-hook recommendation.
