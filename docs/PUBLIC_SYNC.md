# Public sync v1.8.3

Source baseline: private commit `a9d03250520980eea0d99713cf4380a1a18ed624`. Files were copied from the clean checkout; no private Git commits/objects were merged into public history.

## Public distribution differences

* No `License.ps1`, `keygen.ps1`, license payload, remote HWID allowlist or authorization request. The public toolkit runs locally/offline; stability gates remain.
* Hardware declaration starts unconfigured. No personal platform preset, captures, reports, backups, signing material or local machine identifiers are committed.
* Public executable is rebuilt from this public tree. The private executable is not copied. The build cannot include a license.
* Core journalling, WHEA governance, verified load, bounded observer, real topology and conservative runtime policy are synchronized from v1.8.3.
* Additional public follow-up: `framebench -Effective`, clean temporary game state, sampled capture guard, explicit one-pair comparison and native tool logs kept out of the returned JSON object.

## Meaning of Effective

`-Effective` requests an experiment; it is not a positive verdict. `-BaselineFile` reads an existing schema-2 result without editing it. Scenario, graphics settings label, experiment ID, game, warmup and stream are inherited; tool hash and machine/display context must match.

`-PrepareCleanState` explicitly sets only the game's scheduling for that measurement: Normal priority and the measured full group-0 affinity mask, including SMT. It does not reset Windows, BIOS, driver profiles, legacy registry tweaks or GameDVR. The previous process state is journalled before writing and restored in `finally` after measurement, including failure. Original reference priority/affinity are preserved as evidence.

Require recent HeavyQA and no pending journals. The legacy BNQQ Game Watcher and Audio Isolation tasks must be disabled/absent, and no watcher/audio process may be detected. The script never force-kills legacy workers, never silently disables the stability gate and never changes task configuration. Review/migrate legacy state first; a new code publication does not fix existing OS state.

During capture a read-only guard samples identity, priority, affinity, task state and watcher processes every two seconds. A failed/unavailable guard invalidates the candidate. It cannot prove absence of transitions between samples. Guard overhead is additional instrumentation compared with old references and must be held constant in future controlled A/B runs.

The pair report exports average FPS, 1% low, 0.1% low, p99, p99.9 and jitter with absolute and percentage deltas. One historical baseline vs one clean candidate remains `EXPLORATORY_ONE_PAIR`, `Effective=null`. It changes two scheduling variables together and does not isolate a tweak. `compare` still requires three baselines and three candidates interleaved; it rejects candidates with failed integrity checks.

## Command template

Run from an administrative Windows PowerShell after reviewing/migrating legacy tasks and obtaining a valid HeavyQA. Keep the same warmed scenario and graphics configuration. Do not rename a different scene to match the reference.

```powershell
.\bnqq.ps1 framebench -Effective -PrepareCleanState -FrameSeconds 60 -BaselineFile 'ABSOLUTE_PATH_TO_EXISTING_RESULT_JSON'
```

Add `-DryRun` to inspect the plan without starting workers or changing scheduling. New captures and comparisons stay under `%LOCALAPPDATA%\BNQQ\data`; no local reference path is embedded into the public repository.

Current-tree hygiene does not erase the repository's historical public commits. No history rewrite was requested or performed.
