# Explore E3: multipart precedent hunt

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Phase A needs streaming multipart/form-data handling on the bridge (complete route: files + fence; bounded sizes; hash-while-streaming). No multipart handling exists in `local_bridge_server.py`. Task: hunt the whole repo (astrid/, packs/, scripts/, tests/, pyproject deps) for any existing multipart parsing, `email`/`cgi` module usage, streaming file-upload precedents, or reusable bounded-reader utilities. Also check what Python version the project targets (pyproject) and whether `multipart` third-party deps are already present. Recommend: reuse vs hand-roll (and if hand-roll, the minimal safe shape: boundary handling, size caps, hash-while-streaming, temp-file discipline).

Report ranked findings (<300 words) with file:line evidence.
