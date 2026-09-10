# Meta source validation

Read-only CPU validation captured 2026-09-10. No source, branch, worktree,
staging, commit, push, dependency installation, GPU operation, live service
operation, or network operation was performed. Passing tests do not certify
dirty source as integrated or complete.

## Exact source identities

| Repository | HEAD | Tracked-dirty patch SHA-256 | Status after validation |
|---|---|---|---|
| Astrid | 82d09bb91c8a4621695c1d8b6966652cad941ef4 | c47a84e20d846e7294e0e29e01e230e63661e9b878f6c8e3dcd5cf34eaecb403 | unchanged; 52 pre-existing status entries |
| Runtime | afccb430e2a983c968b6a8a96fd630ba3a6262fc | d2ac159c2a59f56cc1b78af4cad9fda252776cedd76b6135ccfb81f587e9f607 | unchanged; 26 pre-existing status entries |

Patch hashes were recomputed after testing and match the pre-test audit.
PYTHONDONTWRITEBYTECODE=1 and pytest -p no:cacheprovider were used. No new
__pycache__ or .pytest_cache directories were observed in the selected trees.

## Bounded test results

Astrid, from <workspace>/Astrid:

    PYTHONDONTWRITEBYTECODE=1 pytest -q -p no:cacheprovider --disable-warnings
    tests/core/timeline/test_expand_shots.py
    tests/core/timeline/test_timeline_visualize_select.py
    tests/packs/rendering/test_managed_timeline_render.py
    tests/sdk/test_host_bootstrap_source_identity.py
    tests/sdk/test_timeline_filmstrip.py
    tests/sdk/test_timeline_filmstrip_invocation.py
    tests/stage1/test_host_bootstrap_manifest_luna.py
    tests/stage1/test_invocation_runtime_cutover.py
    tests/stage1/test_pack_host_interpreter_identity.py
    tests/stage1/test_sdk_explicit_boundary_luna.py
    tests/stage1/test_vendored_workspace_client_parity_luna.py
    tests/test_generic_host.py
    tests/test_shot_grouping.py
    tests/v10/test_domain_cli_projects_timelines.py
    tests/test_auth.py
    tests/test_omp_agent.py
    tests/test_version_reporting.py

Result: 276 passed in 18.14s.

Runtime, from
<workspace>/banodoco-workspace-runtime-execution-20260909:

    PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. pytest -q -p no:cacheprovider --disable-warnings
    tests/test_generated_client.py
    tests/test_realm_admission_hardening.py
    tests/test_receipt_migration.py

Result: 31 passed in 1.61s.

The first Runtime attempt omitted PYTHONPATH=. and failed collection with
ModuleNotFoundError: runtime_protocol in the realm-admission and receipt
modules. The passing rerun used the same bounded selection with PYTHONPATH=.;
this was an environment/path correction, not a product fix.

## Marker-only publication scan

The scan covered exactly the selected candidate paths in
meta-source-selection.json. It emitted only file:line:type, never values. No
selected path matched a private-key block, AWS-key-shaped value,
token-shaped literal, or URL-embedded credential.

Expected source secret-name/handling references (no embedded value):

    Astrid/astrid/core/execution/generic_host.py:529 [secret-name-reference]
    Astrid/astrid/core/execution/generic_host.py:2151 [secret-handling-no-value]
    Astrid/astrid/core/execution/generic_host.py:2154 [secret-name-reference]
    Astrid/astrid/core/execution/generic_host.py:2155 [secret-name-reference]
    Astrid/astrid/sdk/workspace_client.py:145 [secret-name-reference]
    Astrid/astrid/sdk/workspace_client.py:153 [secret-name-reference]
    Astrid/astrid/core/auth.py:33 [secret-name-reference]
    Runtime/runtime_protocol/server.py:127 [secret-like-field-reference]
    Runtime/runtime_protocol/store.py:631 [secret-like-field-reference]
    Runtime/runtime_protocol/store.py:1465 [secret-like-field-reference]
    Runtime/runtime_protocol/store.py:1933 [secret-like-field-reference]
    Runtime/runtime_protocol/store.py:1982 [secret-like-field-reference]
    Runtime/tools/astrid_migrate/live.py:838 [secret-like-field-reference]

Test-only contract/placeholder references (not credentials):

    Astrid/tests/sdk/test_host_bootstrap_source_identity.py:41 [test-fixture-secret-contract]
    Astrid/tests/sdk/test_host_bootstrap_source_identity.py:162 [test-fixture-secret-contract]
    Astrid/tests/sdk/test_host_bootstrap_source_identity.py:257 [test-fixture-secret-contract]
    Astrid/tests/stage1/test_sdk_explicit_boundary_luna.py:31 [test-fixture-secret-contract]
    Astrid/tests/stage1/test_sdk_explicit_boundary_luna.py:41 [test-fixture-secret-contract]
    Astrid/tests/stage1/test_sdk_explicit_boundary_luna.py:45 [test-fixture-secret-contract]
    Astrid/tests/test_generic_host.py:192 [test-fixture-secret-contract]
    Astrid/tests/test_generic_host.py:511 [test-fixture-secret-contract]
    Astrid/tests/test_generic_host.py:531 [test-fixture-secret-contract]
    Astrid/tests/test_generic_host.py:894 [test-fixture-secret-contract]
    Astrid/tests/test_auth.py:10 [test-fixture-secret-contract]
    Astrid/tests/test_auth.py:22 [test-fixture-secret-contract]

One machine-local path appears in a test assertion and is not a secret:

    Astrid/tests/sdk/test_timeline_filmstrip_invocation.py:93 [machine-local-path]

The scan is marker-based, not a cryptographic secret detector. Final
publication still requires human review of selected files and reachable
history. Source handlers that read environment/file credentials must remain
value-free, and test-only placeholders must not become real credentials.

## Preservation decision

The bounded CPU evidence supports preserving the selected Astrid and Runtime
dirty paths for later handover. It does not authorize staging or pushing, does
not validate unselected repositories, and does not settle Astrid/Runtime
composition. Attach these exact HEADs, patch hashes, commands/results, and
dirty manifests to the authorized .otto/portfolios/astrid-delivery snapshot.
