## Discussion 01: Should the homelab keep beads-rust as its agent task tracker?

**Status:** closed (round 1 plus a narrowed follow-up).
**Date:** 2026-11-25
**IC:** Claude (Claude Code session leading the round)
**Subject:** beads_rust as the work queue for nix-clan-homelab,
unified-nix-configuration and nix-router-optimized, against original beads
(Go), GitHub Issues, git-bug, Markdown files and Linear/Symphony.
**Protocol:** [agent-roundtable](https://github.com/deepwatrcreatur/agent-roundtable)
`docs/design/DISCUSSION_LEADER_SUMMARY.md`; satisfaction markers per question.
**Roster:**
- Codex (`codex exec`, read-only sandbox)
- Gemini (`agy -p`)
- Claude (`claude -p`)
- Copilot (`copilot -p`; its round 1 answer is headed "Claude's Answer",
  which is how the CLI signed it, not a second Claude seat)
- DeepSeek (direct API, model reported as `deepseek-flash`)
- OpenCode enrichment seat: the first attempt
  (`opencode/nemotron-3-super-free`) failed with a server error; the retry
  with `opencode/big-pickle` was substantive. Round 1 only.

Full quorum in both rounds. Raw answers are in the appendix.

### Context given to every voice

Verified on 2026-11-25:
- nix-clan-homelab keeps its queue on `main`: 87 issues, and 69 of 182
  commits on `main` touch `.beads/issues.jsonl` (38%).
- nix-router-optimized (27 issues) and unified (22) keep theirs on a
  `beads-queue` branch, written through the `beads-q` wrapper.
- Problems hit:
  1. client-minted comment and child ids collided and broke fresh clones
     (fixed upstream in v0.7.0, while these repos pinned 0.1.45);
  2. claims are local until they reach `main`;
  3. conflicted JSONL cannot be hand-edited;
  4. about 40 lines of beads rules in AGENTS.md, plus recovery files;
  5. a fast-moving upstream with many past corruption reports.
- Alternatives with star counts and the prior agent-roundtable conclusions:
  round 145 (Beads and `bv` are the strongest task-selection layer) and
  round 11 (Symphony's tracker-driven, workspace-per-issue model).

The prompt is reproduced at the start of the appendix.

### IC fact-check (between rounds)

- **`beads-q` already does compare-and-swap.** `pkgs/beads-queue.sh` in
  unified fetches, hard-resets a queue worktree to the remote branch,
  rebuilds the database, runs the command, exports, commits and pushes
  without force, retrying from the new tip on rejection. `update --claim`
  fails with `CLAIM_CONFLICT` if the rebuilt database already has a claim.
  DeepSeek's round 1 view that a queue branch only "narrows the window" did
  not account for this.
- **Original beads is no longer JSONL in git.** The `gastownhall/beads`
  README says it is "powered by Dolt" with hash-based ids (`bd-a1b2`).
  Claude, Gemini, DeepSeek and OpenCode assumed it shares beads_rust's
  model; Codex had it right.
- **beads_rust v0.7.6 still mints integer ids locally.** Tested on a copy
  of this queue: a comment-id collision that merges cleanly in git is
  renumbered on import and both comments survive; same-parent child ids
  usually conflict in git.
- **GitHub has a REST API for issue dependencies and sub-issues;
  assignment is not compare-and-swap.**

### First-pass convergence (round 1)

All six voices recommended **stay on beads_rust v0.7.x and change how it is
used**, with GitHub Issues as the fallback. They agreed on:

1. **The queue on `main` is the largest self-inflicted cost.** Bead state
   rides in feature PRs, so claims wait for merges and every PR can conflict
   on `issues.jsonl`. Move nix-clan-homelab to a `beads-queue` branch like
   the other two repos.
2. **`beads-q` is the only writer.** Agents never commit `.beads/`; CI
   rejects feature PRs that touch it.
3. **Pin one tested version everywhere and upgrade on purpose.** The 0.1.45
   pin turned a fixed upstream bug into months of breakage. Test each bump
   against copies of the real queues (fresh import, export round trip).
4. **Shrink the AGENTS.md beads section** to a few commands. Rules that
   compensate for the layout disappear with the layout.
5. **Diagnosis:** id collisions and JSONL merge fragility are inherent to
   client-minted ids in git; the severity was version lag; the frequency was
   the queue-on-`main` layout.

Why not move: beads' value is graph-aware task selection (`ready --json`,
blockers, `bv`). GitHub Issues fixes ids and conflicts but needs a
hand-written "ready" query and still has no atomic claim. Markdown files and
git-bug lack a dependency graph and a ready query. Linear/Symphony adds a
paid service and credentials for one operator.

### Disagreements and the narrowed follow-up

Round 1 split on four points. The follow-up gave every voice the fact-check
above and asked only about them.

| Point | Round 1 | Follow-up result |
| --- | --- | --- |
| Are claims through a queue branch atomic? | Claude and Codex: yes, if the wrapper retries and re-validates. DeepSeek: no, only narrower. Gemini and DeepSeek rated GitHub assignment atomic; Claude and Codex did not. | All five: `beads-q` claims are atomic enough, **conditional on a deliberate two-client race test**. All five: GitHub assignment is last-write-wins. Claude noted GitHub can still give an atomic claim by creating a `claim/<issue>` ref, which fails if it exists. |
| Original beads (Go) | Most dismissed it as the same model. | All five: Dolt plus hash ids is a real design improvement but not worth a second remote, sync tool and backup target at this scale. Revisit if agents need offline writes or the fleet of repos and agents grows. |
| Duplicate-id CI check | Copilot: keep forever. DeepSeek: retire after a clean month. | All five: **keep permanently, run on the queue branch.** It is cheap and the only guard against writes that bypass `beads-q`; a quiet month proves nothing about a rare collision. |
| How a feature PR relates to its bead | Copilot proposed requiring the first commit to claim the bead; others banned `.beads/` from feature PRs. | Four voices: **ban `.beads/` from feature PRs**; claim through `beads-q` before starting; reference the bead with a `Bead: <id>` trailer (optionally `bead/<id>-<slug>` branch names); CI checks the id exists and is `in_progress` on `beads-queue`; close through `beads-q` after merge. Copilot's own condition reduces to the same outcome, since it keeps `.beads/` writes inside `beads-q`. |

### Closure

**Decision: keep beads_rust (v0.7.6) and change the layout and rules.**

1. Move nix-clan-homelab's queue from `main` to a `beads-queue` branch
   written only by `beads-q`. Protect that branch against force-push.
2. CI on `main`: reject PRs that touch `.beads/`; require a `Bead: <id>`
   reference that exists and is `in_progress` on `beads-queue`.
3. CI on `beads-queue`: the duplicate-id check (kept permanently), a fresh
   rebuild from JSONL, and an export round trip with no diff.
4. Run the race test before relying on claims: K clones (2, 4, 8) claim the
   same bead at a barrier, about 100 repetitions, with a hook that rejects
   the first push. Exactly one winner, the rest `CLAIM_CONFLICT`, one claim
   commit per round, linear history.
5. Pin one beads_rust version across repos; bump through a PR whose CI
   imports copies of every queue. Upgrade within a few weeks of releases
   that touch import, merge or schema.
6. Cut the AGENTS.md beads section to the commands and one pointer to the
   recovery procedure; move the rest into `beads-q` and CI.

**Exit criteria (next month).** Reconsider, most likely moving to GitHub
Issues with a small `gh` ready script and ref-based claims, if any of these
happen after the queue branch and v0.7.6 are live:
- a double claim, a lost mutation, or a queue tip that fails a clean import;
- rebuild failures or new `.br_recovery` files on the queue branch;
- an upgrade that needs manual data repair;
- more than about an hour of operator time on queue repair, or two manual
  recoveries;
- push retries routinely above about three per claim, or claims queuing
  long enough that agents wait;
- `bv` and graph triage going unused, which removes beads' main advantage.

Signals to stay: zero duplicate-id hits, zero `.beads/` diffs in feature
PRs, an AGENTS.md beads section of ten lines or fewer.

Tracked as beads `nch-a9a.8` (move the queue and add the CI rules), `nch-a9a.9` (race test) and `nch-a9a.10` (shrink AGENTS.md). `nch-a9a.7` (v0.7.6 rollout) now keeps the duplicate-id check.

### Race test results (`nch-a9a.9`, 2026-11-26)

Closure item 4, run with `scripts/beads-q-race-test.sh`:
- K clones of one local bare remote claim the same bead at a barrier, 100
  rounds per run. Separate clones take separate `beads-q` locks, so they
  behave like separate machines.
- A pre-receive hook rejects the first push of every round, so the retry
  path runs every round.
- Each round passes only with exactly one exit 0, K-1 claim conflicts and
  one claim commit.
- At the end the history must be linear, and every round's bead must be
  present and assigned to its winner, both in the final JSONL and in a
  database rebuilt from it.

| beads-rust | K | Rounds | Failed rounds | Client retries | Merges |
| --- | --- | --- | --- | --- | --- |
| 0.1.45 | 2 | 100 | 0 | 123 | 0 |
| 0.1.45 | 4 | 100 | 0 | 303 | 0 |
| 0.1.45 | 8 | 100 | 0 | 700 | 0 |
| 0.7.6 | 2 | 100 | 0 | 126 | 0 |
| 0.7.6 | 4 | 100 | 0 | 300 | 0 |
| 0.7.6 | 8 | 100 | 0 | 700 | 0 |

- **No double claim and no lost update in 600 rounds.** Every run ended
  with 101 commits (seed plus one claim per round) and every bead assigned
  to its winner.
- **This is the second run.** In the first, the final check only looked at
  beads that survived, so a claim that dropped an earlier bead would have
  passed (Codex on PR #75). The harness now checks every round's bead; a
  mutation that drops `tst-r2` after a correct claim fails it.
- **The first run found one transient fetch failure.** In round 70 of 0.7.6
  with K=8, the claim was still decided correctly (one winner, six
  conflicts, one claim commit). The eighth client exited 128 with
  `couldn't find remote ref refs/heads/beads-queue`: its fetch listed refs
  while another push renamed the loose ref into place, and `beads-q`
  treated a failed fetch as fatal. That was about 1 in 2,400 heavily
  contended calls. unified PR #266 makes `beads-q` retry the fetch
  (`nch-a9a.11`); a run of K=8 for 100 rounds with that version was also
  clean.
- **0.1.45 words the conflict differently.** It reports "issue … already
  assigned to …" with exit 4 instead of `CLAIM_CONFLICT`.
- **The harness can fail.** `scripts/beads-q-race-broken.sh` claims on a
  stale copy and force-pushes, as a writer bypassing `beads-q` would. It
  produced two or three winners in every round.
- **Kept as a regression check.** `checks.beads-q-race` runs K=4 for 10
  rounds with the packaged `beads-q`, plus the negative control, under
  NixCI.

Exit criterion "a double claim after compare-and-swap claiming lands" is
not met.

---

## Appendix: prompts and raw answers

Answers are verbatim. Claims in them were not all verified; the IC fact-check above takes precedence.

### Round 1

<details>
<summary>Round 1 prompt</summary>

ROUNDTABLE: Should this homelab keep beads-rust as its agent task tracker?

You are one voice in a multi-agent design discussion (Codex, Gemini, Claude, Copilot, DeepSeek). Answer independently. Do not run shell commands or edit files. If you cite a fact you cannot verify, say it is unverified. Keep the answer under 1200 words.

## Context (verified by the discussion leader on 2026-11-25)

The operator runs a NixOS homelab from git repos (nix-clan-homelab, unified-nix-configuration, nix-router-optimized). Most work is done by coding agents (Claude Code, Codex, others) running in parallel, each in its own git worktree, landing changes by GitHub PR with review bots. One human operator approves and sometimes merges.

Task tracking today uses beads_rust (`br`, installed as `beads-rust`), an agent-first tracker storing issues in SQLite with a JSONL export (`.beads/issues.jsonl`) committed to git:
- nix-clan-homelab: queue on `main`; 87 issues (42 open). 69 of 182 commits on main touch `issues.jsonl` (38%).
- nix-router-optimized and unified: queue moved to a separate `beads-queue` branch (27 and 22 issues), driven by a wrapper script `beads-q` that resets a worktree to the remote branch, rebuilds the DB, runs the command, exports and pushes.
- Agents use: `ready --json` (unblocked work), `update --claim --actor`, `close --reason`, `comments add`, parent/child ids (`nch-sny.41`), dependencies (blocks, parent-child, related), labels (`live`, `owner:claude`).

Problems actually hit:
1. Ids are minted from each clone's local counter. Two branches each added comment id 23; both merged cleanly in git; every fresh clone then failed to build its DB (UNIQUE constraint). Child ids `<parent>.N` collide the same way. Fixed upstream in beads_rust v0.7.0 (colliding comment ids renumbered on import; child-id collisions refused and resolved with `sync --merge`). The repos pinned 0.1.45 for months; an upgrade to v0.7.6 is in review. A local CI check for duplicate ids was added as a stopgap.
2. A claim is only local until its commit reaches main, so two agents can claim the same bead. AGENTS.md compensates with rules (land claims in a tiny PR right away). Shared queue branch is the planned fix.
3. Conflicted `issues.jsonl` must not be hand-edited (0.1.45 skipped records whose `updated_at` was not newer and wrote old versions back); documented recovery: take main's file, rebuild DB, redo your own commands.
4. AGENTS.md carries roughly 40 lines of beads rules. Fresh worktrees sometimes failed to rebuild; recovery files accumulate in `.beads/.br_recovery`.
5. Upstream beads_rust: 1,163 stars, 69 releases, very fast release cadence (0.1.45 to 0.7.6 in about three months); its tracker shows many closed reports of SQLite corruption, import field-shifts and sync data loss under concurrent agents, mostly fixed. Schema migrations between versions.

Alternatives on the table (verify what you can; star counts from GitHub API today):
- Original beads (Go, now `gastownhall/beads`, 29k stars, 1,829 open issues, v1.3.4 2026-11-04), which beads_rust reimplements.
- GitHub Issues (+ sub-issues, Projects, labels) via `gh`. Agents already need `gh` for PRs. Server-side ids, no merge conflicts, but needs network and tokens, and history lives outside the repo.
- Linear, the hosted tracker that OpenAI's Symphony is reported to target (unverified; Symphony: Elixir reference implementation, 28k stars; polls a tracker, isolated workspace per issue, agent per workspace, `WORKFLOW.md` policy) was built around.
- git-bug (Go, 10.9k stars): issues stored as git objects, offline, distributed, bridges to GitHub.
- Backlog.md (TypeScript, 7.5k stars): one markdown file per task in the repo.
- Plain markdown work-item files (the operator's agent-roundtable repo uses `docs/work-items/NN-*.md` with a README status table).

Prior local discussions (agent-roundtable rounds) concluded: isolation (worktrees) is the mutation boundary; a separate coordination/task-selection layer is needed, and Beads + `bv` (graph-aware triage) is the strongest under-admitted task-selection layer (round 145). Symphony validated a tracker-driven, workspace-per-issue model (round 11).

## Questions (mark each with exactly one of `[satisfied]`, `[satisfied-conditional: X]`, `[needs more evidence: X]`)

Q1. Diagnosis. Which of the five problems are inherent to beads' design (repo-local DB + JSONL in git, client-minted ids), which were version/rollout lag, and which are self-inflicted by how these repos use it (queue on `main`, every agent committing bead state into feature PRs)?

Q2. Options. Compare: (a) stay on beads_rust v0.7.x and refine practices; (b) switch to original beads (Go); (c) GitHub Issues as the queue; (d) git-bug; (e) markdown files (Backlog.md or work-items); (f) Linear/Symphony-style hosted tracker. Judge each on: parallel agents without collisions, claim atomicity, offline use, agent ergonomics (one command to get ready work as JSON), dependency graph, history and auditability, operational burden for one operator, lock-in.

Q3. Recommendation. Stay, refine, or move? If stay: the 3-5 concrete practice changes that matter most (for example: queue branch everywhere vs on main, who may write bead state, upgrade policy, checks). If move: target, migration path, and what is lost.

Q4. Exit criteria. What evidence over the next month should trigger reconsidering your answer?

</details>

<details>
<summary>Codex</summary>

**Keep beads-rust for a one-month trial with a dedicated queue branch in all three repos.** Its ready-work query and dependency graph already fit how agents pick tasks. The trial should answer whether `beads-q` can make claims reliable and keep recovery work within one operator’s budget. GitHub Issues is my fallback because the agents and operator already coordinate PRs there.

### Q1. Diagnosis [satisfied]

| Problem | Cause |
|---|---|
| 1. Duplicate IDs broke fresh imports | Independent clones minting IDs from the same counters creates the collision risk. Git’s line merge can accept both records because it has no knowledge of ID uniqueness. Per the supplied incident history, v0.7.0 repairs comment collisions on import and detects child-ID collisions for explicit reconciliation. The long pin prolonged exposure to the import failure. |
| 2. Double claims | Independent local databases cannot arbitrate a shared claim. Claim PRs add a review and merge delay. A dedicated branch helps only if the wrapper reports success after the remote accepts the claim and handles concurrent updates correctly. |
| 3. Conflict recovery | Concurrent JSONL edits can conflict by design. Stale records surviving an edit and being written back was the reported v0.1.45 behavior. Feature PRs made those conflicts part of ordinary code delivery. |
| 4. Rules, rebuilds, recovery files | Reconstructing local state is part of this storage model. Failed rebuilds and recovery-file accumulation are implementation or operational symptoms whose specific causes are unverified. Per-worktree writers and queue changes in feature PRs expanded the rules agents had to follow. |
| 5. Upstream churn | Release cadence, migration compatibility, and reported corruption or sync bugs are implementation and rollout risks. The architecture still requires reliable import, export, and reconciliation across replicas. |

### Q2. Options [satisfied-conditional: verify exclusive claims and ready-work behavior in the chosen deployment]

| Option | Concurrency and offline use | Agent workflow, audit, and operator cost |
|---|---|---|
| **beads-rust v0.7.x** | Offline reads and local edits. A single authoritative queue per repo can prevent conflicting publications if writes are replayed against the latest tip and claims succeed only after publication. | Existing `ready --json`, graph, and `bv` workflow. Git queue history and portable JSONL, with some dependence on Beads schemas and tooling. Wrapper and upgrade maintenance remain. |
| **Original Beads (Go)** | Current docs describe embedded Dolt and a shared server mode for concurrent agents. Use one shared authority for exclusive claims and verify the exact deployment with a race test. Embedded mode supports local work. | Preserves Beads-style JSON and graph workflows. Dolt adds versioned history, a migration, and a backup and restore workflow. Greater runtime burden and Dolt dependence. [Configuration](https://github.com/gastownhall/beads/blob/main/docs/reference/configuration.md) · [Concurrency docs](https://github.com/gastownhall/beads/blob/main/docs/reference/advanced.md) |
| **GitHub Issues** | Server-issued IDs avoid clone collisions. Requires connectivity and tokens. Treat assignment as advisory unless a dispatcher or verified conditional write enforces exclusive claims. | One `gh` wrapper can emit ready JSON from open state, assignments, and blocker status. Native sub-issues and blockers. Issue timelines and PR links give the operator one place to review work. Low service overhead, with provider-hosted history and export work for portability. [Dependency API](https://docs.github.com/en/rest/issues/issue-dependencies?apiVersion=2026-03-10) · [GitHub CLI](https://cli.github.com/manual/gh_issue_list) |
| **git-bug** | Offline-first Git-object storage avoids a shared JSONL file. Distributed replicas still need a shared authority for exclusive claims. Behavior for concurrent edits to one issue is unverified here. | Git-backed history and bridges aid portability, though tracker refs and bridge mappings add upkeep. Beads-equivalent dependency traversal and ready JSON are unverified. [git-bug](https://github.com/git-bug/git-bug) |
| **Backlog.md / plain Markdown** | Offline. Separate files reduce merge overlap. Concurrent numeric IDs and claims still need coordination. | Backlog.md offers dependency-aware readiness and JSON. Plain files need a parser and agreed dependency semantics. Both give readable Git history and low format lock-in. Maintaining a dispatcher can erase the simplicity advantage. [Backlog.md releases](https://github.com/MrLesk/Backlog.md/releases) |
| **Linear / Symphony-style** | Hosted IDs and shared state avoid clone collisions. Live dispatch needs connectivity and credentials. Exclusive claims across dispatcher instances are unverified. | Linear is a verified Symphony adapter. The Elixir reference also supports GitHub Issues. Ready-work selection comes through the adapter and workflow policy. Tracker history stays with the provider, while Symphony adds a service to operate. [Symphony spec](https://github.com/openai/symphony/blob/main/SPEC.md) · [Elixir implementation](https://github.com/openai/symphony/blob/main/elixir/README.md) |

### Q3. Recommendation [satisfied-conditional: v0.7.6 passes restore and concurrent-claim checks]

1. **Make `beads-queue` authoritative in all three repos.** Route every mutation through `beads-q`. Feature PRs reference bead IDs and carry code changes.
2. **Make remote acceptance the claim boundary.** Use isolated scratch state or lock the entire transaction when sharing a queue worktree. Publish with a normal fast-forward push. On rejection, rebuild from the latest tip and recheck eligibility before replaying a claim. A claimant who loses the race gets an explicit failure. Before retrying a comment or creation after an ambiguous push result, check whether the original write landed.
3. **Pin one tested Nix version for all writers.** Stage v0.7.6 against copies of all three queues. Check fresh import, export and reimport, and preservation of comments, child IDs, and dependency edges. Record the pre-upgrade queue refs and stop older clients from writing after cutover.
4. **Test the publication path and shorten the agent rules.** Race two independent clients for one task and verify exactly one winner. Check duplicate IDs and fresh import before publication. Reduce `AGENTS.md` to normal commands and link to one recovery procedure.

### Q4. Exit criteria [satisfied]

Reconsider immediately after **one confirmed lost mutation, one pair of successful claims for the same task, or one published queue tip that fails a clean import**. Over the month, also reconsider after **two manual queue recoveries or more than one hour of operator time spent on queue repair**, excluding planned rollout and testing. Log claim attempts and queue writes so a quiet month carries the right weight. I’d want at least 20 real claims and the deliberate race test before calling the trial conclusive.

If a threshold trips, pilot GitHub Issues in one repo. Freeze Beads writes at cutover, preserve the queue ref as an archive, and migrate open work with original IDs, comments, labels, and mapped parent and blocker links. Verify the graph and use one dispatcher for exclusive assignment. That gives up offline queue mutation and native `bv` triage, while keeping historical Beads records available in Git.

</details>

<details>
<summary>Gemini (agy)</summary>

### Perspective: Gemini (Autonomous Systems & Orchestration)

---

### Q1. Diagnosis [satisfied]

The failure modes experienced in the homelab stem from three distinct layers: architectural assumptions, stale software pinning, and an anti-pattern in repo usage.

1. **Inherent to Beads’ Design (Distributed DB + Git JSONL):**
   * **Client-side ID generation:** In any distributed system without a centralized authority or true collision-resistant IDs (e.g., UUIDv7/ULID), auto-incrementing integer counters (`.N` child IDs, comment IDs) will collide whenever parallel branches mint IDs concurrently.
   * **Dual-state serialization mismatch:** Maintaining a relational SQLite cache derived from a flat, version-controlled JSONL log guarantees 3-way merge conflicts when two actors touch the same issue record concurrently. Git merges line-by-line; relational databases require ACID consistency.

2. **Version / Rollout Lag:**
   * **Pinning v0.1.45:** The silent record drop (skipping records where `updated_at` was not strictly newer) and fatal crashes on duplicate IDs were early-stage implementation defects. Beads_rust moved from v0.1.45 to v0.7.6 specifically to introduce collision renumbering, `sync --merge`, and import resilience. Running an immature, pre-v0.5 storage tool in production for months while parallel agent concurrency grew turned solved upstream bugs into persistent operational friction.

3. **Self-Inflicted Usage Patterns (The Primary Culprit):**
   * **Committing queue state to `main` via feature worktrees:** 38% of commits on `main` touching `issues.jsonl` indicates that task state was treated as code state. When an agent binds its claim (`update --claim`) or comments into a long-lived feature branch, the claim is completely invisible to all peer agents until that feature PR is approved and merged. This guarantees race conditions and claim collisions.
   * **Worktree contamination:** Every agent worktree rebuilding its own SQLite database against stale git checkouts inevitably spawns recovery files (`.beads/.br_recovery`) and dirty worktrees.

---

### Q2. Options Comparison [satisfied]

| Option | Parallel Safety & Claims | Ergonomics (`ready --json`, DAG) | Offline & Locality | Operational Burden & Stability | Lock-in |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **(a) beads_rust v0.7.x** | **Medium**: Claims require centralized queue branch; ID renumbering handled in v0.7+. | **High**: Native graph resolution, blocking dependencies, and instant agent triage. | **High**: Fully local SQLite + JSONL. | **Medium**: Requires dedicated queue wrapper (`beads-q`) and monitored upstream upgrades. | **Low**: Git-tracked JSONL. |
| **(b) Original beads (Go)** | **Medium**: Same distributed file model; subject to same git synchronization semantics. | **High**: Reference implementation for beads syntax. | **High**: Fully local. | **Medium**: Higher upstream issue backlog (1.8k issues); Go binary footprint vs NixOS Rust toolchain. | **Low**: Plain JSONL. |
| **(c) GitHub Issues (`gh`)** | **High**: Centralized API; atomic claims and server-minted global IDs. No merge conflicts. | **Low-Medium**: Sub-issues exist, but true graph DAG / topological `ready` queue requires custom agent tooling. | **None**: Requires active network, tokens, and rate-limit management. | **Low**: Zero DB repair, zero worktree contamination; shifts burden to token security. | **Medium**: GitHub vendor lock-in. |
| **(d) git-bug** | **High**: Avoids flat JSONL merge conflicts by storing issues as native git object trees. | **Low**: Lacks first-class DAG dependency blockers / graph-aware agent triage. | **High**: Pure offline distributed git. | **Medium**: Niche toolchain; limited ecosystem support for agent workflows. | **Low**: Git-native data structures. |
| **(e) Markdown Files** | **Very Low**: Frequent git merge conflicts on index tables; race conditions on claims. | **Low**: Flat files require agents to grep/parse text; no native graph or cycle detection. | **High**: Plain text. | **High**: Constant conflict resolution and token-wasting file parsing. | **Zero**: Markdown. |
| **(f) Hosted (Linear / Symphony)** | **High**: Native ACID locking, webhook events, and server-side states. | **High**: Structured states; *(unverified: Symphony’s workspace-per-issue Elixir implementation natively assumes Linear-style webhooks)*. | **None**: Fully hosted SaaS. | **Low maintenance, High setup**: Overkill for a single-operator homelab; introduces cloud dependency. | **High**: Proprietary API. |

---

### Q3. Recommendation: Refine beads_rust on v0.7.x [satisfied-conditional: Strict queue isolation]

**Verdict: Stay and refine beads_rust (v0.7.6+). Do not switch to GitHub Issues or flat files yet.**

The primary value of beads is not issue tracking; it is **graph-aware agent task dispatch** (`ready --json` with dependency blocking). Neither GitHub Issues nor plain Markdown provides topological DAG scheduling out of the box without writing bespoke orchestration middleware. However, keeping beads requires eliminating the self-inflicted patterns that broke it.

#### 4 Concrete Practice Changes That Matter Most:

1. **Absolute Queue Isolation (`beads-queue` branch everywhere):**
   * Completely purge `issues.jsonl` from `main` and all feature branches in all repos.
   * Task state must never travel through feature PRs. All beads operations must run strictly against the orphaned/isolated `beads-queue` branch using the `beads-q` wrapper.
   * Worktrees remain strictly for NixOS code mutations; the task DB lives in a single shared path (or ephemeral cache) decoupled from feature checkouts.

2. **Atomic Mutate-and-Push Loop for Claims:**
   * Claims and closes cannot be deferred. The `beads-q` script must execute an atomic transaction: `fetch -> rebase/reset -> apply br command -> commit -> push`. If the push fails due to a concurrent write, it retries immediately. This turns claim latency from "hours (PR lifecycle)" into "seconds (git push loop)".

3. **Treat `AGENTS.md` as an Operational Gate:**
   * Strip the 40 lines of tribal recovery lore from `AGENTS.md`. Replace them with one rule: *“Agents interact with tasks exclusively via `beads-q <command>`. Agents shall never add `.beads/` files to a feature git commit.”*
   * Add a pre-commit / CI lint that rejects any PR modifying `.beads/` files on `main`.

4. **Disciplined Nix Flake Upstream Pinning:**
   * Upgrade to `v0.7.6` immediately to benefit from collision renumbering.
   * Treat `beads_rust` as an actively evolving alpha: test releases against a scratch clone before bumping the homelab flake pin, avoiding 6-month stale lags.

*If this refinement fails, the only viable migration target is **GitHub Issues via `gh`**, sacrificing offline operation and native DAG filtering in exchange for absolute claim atomicity and zero maintenance burden.*

---

### Q4. Exit Criteria [satisfied-conditional: 30-day evaluation window]

Reconsider this decision and migrate directly to GitHub Issues if, over the next 30 days under v0.7.6 and the dedicated `beads-queue` branch:

1. **Corrupted State / DB Lock Failures:** Fresh agent worktrees or `beads-q` invocations produce SQLite constraint errors or spawn new recovery files in `.beads/.br_recovery` more than once.
2. **Claim Collisions Under Concurrency:** Two agents claim the same bead despite the atomic `beads-q` push loop (indicating git transport latency is fundamentally too slow for your agent concurrency level).
3. **Upstream Schema Breakage:** A future minor upgrade of `beads_rust` corrupts existing history or requires manual database intervention to salvage tasks.
4. **Agent Compliance Drift:** Review bots or human operator must reject more than two PRs due to agents inadvertently committing beads artifacts to feature branches.

</details>

<details>
<summary>Claude (claude -p)</summary>

# Roundtable answer: should this homelab keep beads-rust?

## Q1. Diagnosis `[satisfied]`

**Inherent to the design (any repo-local DB with JSONL in git and ids minted on the client):**
- **Problem 1, id collisions, is mostly a design flaw.** v0.7 handled it, but it did not fix the cause. Counters on each clone that share one namespace will collide whenever branches diverge. v0.7 renumbers comment ids and refuses child-id collisions so you can merge them. That turns a broken clone into a manual merge step, which is better but still a step. I believe the original Go beads moved to hash-based ids for this reason (unverified). Child ids of the form `<parent>.N` keep the counter problem, because the order means something.
- **Problem 2, non-atomic claims, is inherent to any tracker replicated through git.** A claim is just a local write until it reaches a shared ref. No practice makes a claim on a feature branch atomic. Only a serialized write to a shared ref can do that.
- **Part of problem 3 is inherent.** Git merges JSONL line by line, not by meaning. A conflict-free textual merge can still be wrong, and a conflicted merge has no safe manual fix.

**Version and rollout lag:**
- **Problem 1's breakage of every fresh clone** came from pinning 0.1.45 for months after upstream had fixed it.
- **Problem 3's bad behaviour:** 0.1.45's last-writer-wins import that skipped records and wrote old versions back.
- **Part of problem 4:** failed rebuilds and the pile-up in `.br_recovery`. These are most likely old import bugs, but I can't confirm that.

**Self-inflicted by how these repos use it:**
- **The queue on `main` in nix-clan-homelab is the main multiplier.** 38% of commits touching `issues.jsonl` means bead state rides in feature PRs. That makes every PR a possible conflict on the queue and delays every claim until the PR merges.
- **Problem 4's 40 lines of AGENTS.md rules** are a tax that this layout causes. Most of them exist to make up for problems 2 and 3 on `main`.

**Problem 5, upstream churn,** is a risk you accept by depending on a young, fast-moving reimplementation. It isn't a design flaw, but it is real and ongoing.

## Q2. Options `[satisfied-conditional: GitHub dependency/sub-issue API behaves as I recall; unverified]`

**(a) beads_rust 0.7.x with a queue branch everywhere**
- **Collisions:** good, as long as nobody writes bead state outside the queue branch.
- **Claim atomicity:** achievable. `git push` rejects any update that is not a fast-forward, which works as a compare-and-swap on the queue branch. If `beads-q` resets, claims, pushes, and retries on rejection (re-checking that the bead is still unclaimed), claims become atomic.
- **Offline:** reads work. Writes need the network once the queue branch is the source of truth, so most of the offline benefit is gone.
- **Ergonomics:** best of the options. `ready --json`, claim and close already exist, and `bv` triage is built on them.
- **Dependency graph:** first-class.
- **History:** in git, though noisy.
- **Burden:** medium. You maintain the wrapper and an upgrade policy.
- **Lock-in:** low. It's JSONL.

**(b) Original beads (Go)**
- Same model, larger community, possibly hash ids (unverified).
- 1,829 open issues means its own churn.
- Switching still involves schema and CLI migration, and it fixes nothing that (a) with a queue branch doesn't.
- It doesn't fix claim atomicity either.
- Worth it only if beads_rust upstream stalls or diverges.

**(c) GitHub Issues**
- **Ids:** assigned by the server, so no collisions and no merge conflicts.
- **Claims:** assignment and labels are not compare-and-swap either. Two agents can both assign themselves, though the race window is seconds, not a PR's lifetime.
- **Dependency graph:** sub-issues exist. Blocked-by relationships exist in recent GitHub (unverified as GA). Getting a "ready" set means writing a GraphQL query that you own.
- **Network and tokens:** agents already need `gh`.
- **History:** sits outside the repo, though it can be exported.
- **Burden:** low for the tracker itself, medium for the "ready" script.
- **Lock-in:** moderate.
- **Bonus:** native linking between PRs and issues, and "closes #N".

**(d) git-bug**
- Distributed, with content-addressed ids, so no collisions.
- No real dependency graph, no "ready" query, weak agent ergonomics.
- Claims are not atomic: the same CRDT-style merge means two claims both "win."
- Poor fit.

**(e) Markdown files (Backlog.md or work-items)**
- Great for a handful of items and for human review.
- With 40+ open items, dependencies and parallel claims, you would rebuild beads badly.
- Claims are as weak as beads-on-`main`.
- Fine for roundtable-style work items, not for the agent queue.

**(f) Linear / Symphony-style hosted tracker**
- Server-side atomic state, a good API, and the model Symphony validated (that it targets Linear is reported but unverified).
- For one operator it adds an account, a SaaS dependency, secret handling in every agent, and vendor lock-in.
- It also gives up the `bv` graph triage that round 145 valued.
- Overkill unless you adopt Symphony itself.

## Q3. Recommendation: stay on beads_rust, but change the architecture, not just the rules `[satisfied-conditional: v0.7.6 upgrade lands cleanly and queue-branch CAS is implemented]`

The fixes that matter are structural, and they are cheap.

1. **Use a queue branch in all three repos and ban bead state from feature PRs.**
   - Move nix-clan-homelab's queue off `main` to `beads-queue`.
   - Add a CI check that fails any PR to `main` that touches `.beads/`.
   - This removes problems 3 and 4 for feature work and most of the pressure behind problem 1.
   - Keep a one-way snapshot on `main` if you want history next to code, for example a periodic bot commit or a weekly export.
2. **Make `beads-q` the only writer, with compare-and-swap semantics.** Each command runs this sequence:
   1. Fetch.
   2. Hard-reset to the remote queue branch.
   3. Rebuild the DB from JSONL. This step must be deterministic and must fail loudly.
   4. Run the command.
   5. Export.
   6. Push without force. On rejection, loop back to step 1 and re-validate. A claim fails if someone else already holds it.

   This turns claims into an atomic operation, and it serializes id minting, so collisions become impossible rather than repaired. Agents never run raw `br` mutations.
3. **Pin the version and upgrade deliberately.**
   - Pin beads_rust in the flake, and bump it only through a PR.
   - That PR's CI runs a fresh-clone rebuild plus a round trip (JSONL to DB to JSONL, which must produce no diff) against a copy of each repo's real queue.
   - Read upstream changelogs for schema migrations.
   - Never let agents run versions that differ from each other. The 0.1.45 situation was a stale pin with no review loop. The fix is a scheduled check, roughly monthly, not chasing every release.
4. **Run CI on the queue branch itself:**
   - duplicate-id check (keep it);
   - fresh rebuild from JSONL;
   - round-trip diff check;
   - a check that `.br_recovery` stays empty.

   A red result on the queue branch is a page-the-operator event.
5. **Shrink the beads section of AGENTS.md to about 5 lines:**
   - "Use `beads-q ready --json`, `beads-q claim`, `beads-q close`."
   - "Never edit or commit `.beads/`."
   - "Put the bead id in the PR title."

   If the wrapper needs explaining, the wrapper is wrong.

**What this keeps:** `ready --json`, the dependency graph, `bv` triage, JSONL you can move away from, no SaaS.

**What it concedes:** writes need the network. That is the honest price of atomic claims, and it is the same price as GitHub Issues.

**Why not move to GitHub Issues now:** it would solve problems 1 and 3 outright. But it would leave claim races, cost the graph and triage tooling, and require building a "ready" query. Once the queue branch exists, beads gives you most of GitHub's coordination properties plus better ergonomics. GitHub Issues is the right fallback, not the first move.

## Q4. Exit criteria `[satisfied]`

Reconsider, most likely moving to GitHub Issues with a small `gh`-based `ready` script, if any of these happen in the next month:

- **Any corruption, rebuild failure or round-trip diff on the queue branch** under 0.7.x with the single-writer wrapper. That would mean the tool itself, not our usage, is unreliable.
- **A double claim after compare-and-swap claiming lands.** That would mean the wrapper or `br` breaks the model.
- **An upgrade that needs manual data repair,** or upstream breaking the JSONL format or the CLI contract again within the month.
- **Operator time on beads recovery above about 1 hour per week,** or agents regularly bypassing `beads-q` (look for raw `.beads/` commits blocked by CI).
- **Push contention:** rejected-push retries routinely above about 3 per claim. That would be a sign that a git ref is the wrong lock at your level of parallelism.

Signals to **stay** and drop the contingency:

- zero duplicate-id CI hits;
- zero `.beads` diffs in feature PRs;
- AGENTS.md beads section at 10 lines or fewer;
- the v0.7.6 upgrade done without data loss.

On the other side, if `bv` triage turns out not to be used in practice, most of beads' advantage over GitHub Issues disappears. That alone would tip me toward moving.

</details>

<details>
<summary>Copilot (copilot -p)</summary>

# Claude's Answer

**Q1. Diagnosis**

- **Inherent to the design**: Client-minted ids with repo-local SQLite + JSONL-in-git is the root cause of problem #1 (comment/child-id collisions) and #3 (jsonl merge conflicts can't be hand-resolved). Any system that mints ids locally and reconciles via git merge will hit this class of bug — it's a CRDT-adjacent problem beads_rust clearly wasn't solving correctly pre-0.7.0. That it needed a dedicated merge/renumber algorithm to fix is evidence the original design underestimated concurrent-writer semantics. `[satisfied]`

- **Version/rollout lag**: The specific collision bugs (#1) and the import field-shift/corruption reports on upstream are a version-lag problem layered on top of the inherent design weakness — v0.7.0 claims to fix it, but the repos sat on 0.1.45 for months. This is partly inherent-design-exposed-a-bug and partly operational (slow upgrade cadence against a fast-moving pre-1.0 dependency, 0.1.x→0.7.x in three months is not a stable foundation to pin against). `[satisfied]`

- **Self-inflicted**: Problem #2 (claim races) and the `main`-branch queue in nix-clan-homelab (38% of commits touching `issues.jsonl`) are operational choices, not beads limitations — the repos chose to put the queue on the integration branch most contested by parallel agents, which maximizes collision surface. The other two repos already proved the fix (queue on a dedicated branch) works better. Problem #4 (AGENTS.md bloat, recovery file accumulation) is a direct symptom of #1-#3 leaking into agent-facing documentation and workflow — it's downstream self-inflicted cost, not a separate root cause. `[satisfied]`

**Q2. Options**

- **(a) Stay on beads_rust v0.7.x**: Best agent ergonomics today (`ready --json` is exactly the single-command interface agents need; dependency graph with parent/child/blocks/related is richer than anything else on the list except git-bug/original-beads). Claim atomicity still weak until queue-branch-everywhere is adopted. Operational burden: ongoing — you're tracking a fast-churning pre-1.0 dependency and absorbing its migrations. Lock-in: moderate (JSONL export is portable, but workflow/tooling is bespoke).

- **(b) Original beads (Go, 29k stars, 1,829 open issues)**: Same architectural class (repo-local DB + ids), so same inherent collision risk unless it has solved merge semantics better — unverified whether it has. 1,829 open issues on a 29k-star repo is a noisy signal, could mean heavy real usage or could mean maintenance strain; I can't tell which without reading issue content, so this is `needs more evidence`. Switching is costly for no clearly demonstrated fix.

- **(c) GitHub Issues**: Server-side ids eliminate collision classes #1 and #2 entirely by construction — strongest claim-atomicity story on the list. Costs: network dependency (agents already need `gh` for PRs, so this isn't a new dependency, just extended use), history lives outside git log (weaker auditability via `git log`, but GitHub's own audit trail is arguably fine), no offline queue browsing. Dependency graph via sub-issues is improving but less mature than beads' typed relations (blocks/parent-child/related) — unverified how complete GitHub's sub-issues API is for programmatic dependency queries today.

- **(d) git-bug**: Git-native ids stored as git objects, offline, distributed — directly solves the "ids minted locally, reconciled via git merge" problem that beads_rust had to patch around, by design (git-bug uses content-addressed/DAG-based ids, not sequential counters) — this is a genuine structural advantage worth weighing. Costs: smaller ecosystem (10.9k stars), unverified whether it has an equivalent `ready --json` single-command ergonomic for agents, and migration effort from beads' dependency graph.

- **(e) Markdown files**: Zero merge-conflict risk on ids (filenames are the id), trivial auditability (`git log` on the file), lowest operational burden, but no dependency graph, no `ready` query — agents would need custom tooling to replicate "give me unblocked work as JSON," which is exactly the gap beads currently fills well. Good for human-legible status, weak for the parallel-agent-selection problem that motivated beads in the first place.

- **(f) Linear/Symphony-style hosted tracker**: Symphony's validation is for a workspace-per-issue model, which matches this homelab's worktree-per-agent approach structurally. But Linear is a new paid external dependency, new credential surface, and the "history lives outside the repo" cost is maximal here — worse than GitHub Issues on auditability since it's not even the platform already hosting the code/PRs. `[needs more evidence: whether Linear's API ergonomics for agent polling actually beat `br ready --json` enough to justify the lock-in]`.

**Q3. Recommendation: Stay, and refine.**

The round-145 conclusion (beads + bv as the strongest under-admitted task-selection layer) still holds — nothing on this list clearly beats beads' dependency-graph + single-command-ready ergonomics for the parallel-agent-worktree pattern this homelab actually uses, and v0.7.0 appears to have fixed the specific collision classes that caused the worst incidents. Moving to GitHub Issues or git-bug would trade a known, now-patched problem for an unverified new set of integration risks, for marginal gain. The concrete changes that matter most:

1. **Queue-on-branch everywhere.** Migrate nix-clan-homelab off `main` onto a `beads-queue` branch using the same `beads-q` wrapper already proven in the other two repos. This alone should cut the 38%-of-commits noise and most of the collision surface in the highest-traffic repo.
2. **Land claims immediately, enforced not just documented.** Turn the AGENTS.md claim-landing rule into a CI check (reject PRs that don't update/claim the bead in the first commit) rather than relying on agent compliance with prose instructions.
3. **Pin upgrade cadence, don't float.** Adopt v0.7.6 now, then set an explicit policy (e.g., upgrade within two weeks of any release touching merge/import/schema) instead of silently drifting for months on a pre-1.0 tool with a 69-release-in-some-months cadence.
4. **Shrink AGENTS.md via tooling, not more prose.** Move the ~40 lines of beads rules into the `beads-q` wrapper and CI checks wherever possible — every rule enforced by a script is one less thing an agent can forget or misread.
5. **Keep the local CI duplicate-id check permanently**, even after upgrading — it's cheap insurance against a regression or an agent on a stale local build.

**Q4. Exit criteria**

Reconsider within a month if: (a) v0.7.6 still produces duplicate-id or corruption incidents after the queue-branch migration — meaning the fix is version-level, not design-level, and the inherent problem is actually unsolved; (b) the `beads-q` wrapper itself becomes a recurring source of recovery-file/DB-rebuild failures in nix-router-optimized/unified at a rate that doesn't improve once nix-clan-homelab adopts it; (c) upstream beads_rust issue tracker shows new concurrent-agent data-loss reports post-0.7.x at similar rates to pre-0.7.x (signal the fix is incomplete, not just newer); or (d) GitHub's sub-issues/Projects API demonstrably closes the dependency-graph gap with a verified `ready`-equivalent query, removing the main reason to prefer beads over tools already native to the existing `gh`-based workflow.

</details>

<details>
<summary>DeepSeek (API)</summary>

## Q1. Diagnosis

**Inherent to the design (repo-local DB + JSONL in git, client-minted ids):**
- Problem 1 (id collisions) is inherent to *client-minted ids in a distributed git workflow*. Any tracker that mints ids locally and merges via git will collide unless ids are content-addressed, server-assigned, or merge-aware. v0.7.0's renumber-on-import and refuse-and-`sync --merge` are mitigations, not eliminations — they still require a human/agent to run a merge step.
- Problem 3 (conflicted JSONL must not be hand-edited) is inherent to storing a mutable DB export in git. Any JSONL-in-git design has this failure mode; the specific "skip records whose `updated_at` isn't newer" bug was version-specific, but the *class* of problem is structural.
- Problem 2 (claim is local until merged) is inherent to *any* git-mediated claim, including a queue branch — a queue branch narrows the window but does not make claims atomic. True atomicity needs a server (GitHub/Linear) or a lock protocol.

**Version/rollout lag:**
- The 0.1.45 pin for months is the direct cause of the severity of problems 1 and 3. v0.7.6 in review is the right move. The fast cadence (0.1.45→0.7.6 in ~3 months) is itself a risk signal, not a bug.
- Problem 4 (worktree rebuild failures, `.br_recovery` accumulation) is partly version lag, partly practice.

**Self-inflicted by how these repos use it:**
- Queue on `main` in nix-clan-homelab (69/182 commits touch `issues.jsonl`, 38%) is the single biggest self-inflicted cost. Every feature PR carries bead state, so every merge is a potential JSONL conflict and every agent must rebuild. The other two repos already moved to `beads-queue`; nix-clan-homelab should too.
- ~40 lines of beads rules in AGENTS.md is a symptom of compensating for the above, not a beads requirement.

Net: 1 and 3 are structural; 2 is structural-but-mitigable; 4 and 5 are mostly lag + practice. The 38% commit rate is the loudest signal.

## Q2. Options

**(a) beads_rust v0.7.x + refined practices.** Parallel agents: OK with queue branch, not atomic. Claim atomicity: no (narrowed window). Offline: yes. Ergonomics: best-in-class (`ready --json`, `--claim --actor`, deps, labels). Dependency graph: strong. History/audit: in-repo, but noisy. Ops burden: moderate (schema migrations, recovery files, upgrade discipline). Lock-in: low (JSONL is portable). **Verdict: strongest fit if practices are fixed.**

**(b) Original beads (Go).** Same conceptual model, larger community (29k stars), but 1,829 open issues and v1.3.4 — maturity is unverified from here. Inherits the same JSONL-in-git structural problems. Migration cost is real and buys little on the failure modes that actually bit you. **Verdict: not worth it.**

**(c) GitHub Issues.** Parallel agents: excellent (server ids, no merge conflicts). Claim atomicity: yes (assignee + label is atomic enough). Offline: no. Ergonomics: `gh issue list --json` is fine but slower and needs auth; sub-issues/Projects are clunky for agent JSON. Dependency graph: sub-issues + task lists, weaker than beads. History: outside repo, but auditable. Ops: low. Lock-in: moderate (GitHub). **Verdict: the serious alternative; loses offline and graph ergonomics.**

**(d) git-bug.** Offline, distributed, git-object storage — avoids JSONL conflicts by design. But agent ergonomics and JSON output are weaker (unverified specifics), and the ecosystem is smaller. **Verdict: interesting, not proven for this workload.**

**(e) Markdown files.** Zero collision risk per-file, trivially auditable, but no dependency graph, no atomic claim, no `ready` query — agents would reimplement triage. Fine for the roundtable repo, wrong for a 40-open-issue parallel-agent queue. **Verdict: no.**

**(f) Linear/Symphony.** Best claim atomicity and workspace-per-issue model; Symphony's design is validated (round 11). But hosted, token-dependent, history outside repo, and the Symphony-target claim is unverified. **Verdict: right shape, wrong cost for a one-operator homelab unless agent throughput justifies it.**

## Q3. Recommendation

**Stay on beads_rust v0.7.x, refine practices.** The structural problems (1, 3) are real but bounded by v0.7.x mitigations plus a queue branch; the alternatives that fix them (GitHub, Linear) trade away offline use and graph ergonomics for a one-operator homelab. Five changes, in priority order:

1. **Queue branch everywhere, including nix-clan-homelab.** Kill the 38% commit rate. Bead state never rides in feature PRs; `beads-q` is the only writer.
2. **Single writer rule.** Only `beads-q` (or one designated agent per repo) mutates the queue branch. Feature-worktree agents read `ready --json` and post claims via `beads-q`, not by editing JSONL.
3. **Upgrade to v0.7.6 and pin with a tested-version file + CI check** that runs `br sync --merge` dry-run and the duplicate-id check on every PR. Treat schema migrations as a scheduled, single-agent operation.
4. **Keep the duplicate-id CI stopgap** until v0.7.6 has run clean for a month; then decide whether to retire it.
5. **Shrink AGENTS.md beads section** to: "read via `beads-q ready --json`; claim via `beads-q update --claim`; never edit `issues.jsonl`; recovery = take main's file, rebuild, redo." The 40 lines exist because the queue was on `main`.

What is lost vs. moving: nothing material. What is *not* fixed: claim atomicity remains best-effort (queue branch narrows the window to seconds); JSONL conflicts remain possible but rare with single-writer.

## Q4. Exit criteria (next month)

Reconsider if **any** of these hold:
- A duplicate-id or JSONL-conflict incident occurs **after** v0.7.6 + queue-branch-everywhere is live (structural failure survived the fix).
- `issues.jsonl` still appears in >10% of main commits in nix-clan-homelab after the queue-branch migration (practice didn't take).
- A second upstream data-loss/corruption report lands against v0.7.x that affects concurrent-agent use, or a schema migration breaks a worktree rebuild twice.
- Agent throughput exceeds what a single-writer queue branch can serve (claims queue up, agents idle waiting on `beads-q`).
- Symphony/Linear adoption becomes concrete in the operator's stack (then re-evaluate (f) on cost, not capability).

If none fire, stay.

</details>

<details>
<summary>OpenCode enrichment seat (big-pickle, retry)</summary>

**Q1. Diagnosis — [satisfied]**

| Problem | Verdict |
|---|---|
| 1. ID collisions | **Inherent + rollout lag.** Client-minted counters plus a cleanly merging JSONL file cannot be globally unique. v0.7.0 mitigates the symptom; it does not create a server-side id authority. |
| 2. Local claims | **Inherent + self-inflicted.** Repo-local state is invisible until committed; queue-on-`main` and claims inside feature PRs make the race routine. A shared branch fixes visibility, not atomicity. |
| 3. Conflict recovery | **Inherent + version bug + self-inflicted.** Merging a derived, timestamp-ordered artifact is fragile by design; 0.1.45’s stale-write behaviour made it destructive; feature-branch writes created the conflicts. |
| 4. Rules/recovery clutter | **Mostly self-inflicted.** DB-per-worktree rebuild is inherent; 40 lines of AGENTS.md, stranded recovery files, and no upgrade policy are local process failures. |
| 5. Corruption/migrations | **Inherent + upstream/rollout.** SQLite-plus-export dual representation, client-side writes, and schema changes are structural risks. The reported fixes are upstream work, not operator misuse; months on 0.1.45 amplified it. |

Net: P4 is ours; P2/P3 are largely ours; P1/P5 are beads’ design, made worse by pinning.

**Q2. Options — [needs more evidence: git-bug/Backlog.md JSON and dependency support; Symphony/Linear claims]**

| Option | Parallel safety & claims | Offline | Ready-as-JSON | Graph | History/audit | Burden / lock-in |
|---|---|---|---|---|---|---|
| (a) beads_rust 0.7.x refined | Collisions mitigated, not eliminated; atomic claims only with serialized shared branch | Yes | Native `ready --json` | Strongest available here (`bv` triage) | Git JSONL diff | Moderate/high; low-medium lock-in |
| (b) Go beads | Same structural issues; switching fixes none of P1/P2/P5; 29k stars/1,829 open issues as supplied | Yes | Similar | Likely similar, parity unverified | Git-based | Migration cost; similar lock-in |
| (c) GitHub Issues | Server ids, authoritative assignee/state; races remain but visible | No | `gh --json` + jq | Sub-issues weaker than beads blocks | Strong server audit | Low operational, tokens/network; high lock-in |
| (d) git-bug | Content-addressed, distributed; claims via labels, not authoritative | Yes | Unverified/likely wrapper needed | Weak/unverified | Excellent git-native | Moderate; low lock-in |
| (e) Markdown/Backlog.md | One file per task avoids most conflicts; status edits are non-atomic | Yes | No native JSON | Links only; Backlog deps unverified | Excellent git diff | Low; very low lock-in; loses `bv` |
| (f) Linear/Symphony-style | Server ids and authoritative state; best for workspace-per-issue orchestration | No | API wrapper needed | Relations supported | Hosted | High; high lock-in; Symphony target claim unverified |

Judgement: (a) preserves the graph-aware selection layer prior rounds favoured at the lowest migration cost; (c) is the credible fallback when authoritative claims matter more than graph triage; (b), (d), (e), (f) each trade away an existing strength without fixing a root cause we cannot fix locally.

**Q3. Recommendation — [satisfied-conditional: 0.7.6 lands and queue writes are serialized]**

Stay on beads_rust 0.7.x and refine, with GitHub Issues as a defined fallback.

1. Move **all** queues, including nix-clan-homelab, to `beads-queue`. Feature worktrees may read bead state but never commit it in feature PRs; expected effect: `issues.jsonl` drops out of `main` entirely.
2. Make `beads-q` the only writer and serialize it: remote lock or compare-and-swap, re-read state under lock, retry push, reject stale claims, log every queue commit. Be honest that this is coordination discipline, not native atomicity.
3. Land v0.7.6 now, pin one version in Nix across repos, test migrations on a fixture clone, keep the duplicate-id and post-export schema checks, and retain a periodic JSONL backup.
4. Ban hand-editing; archive `.br_recovery` only after a verified rebuild; shrink AGENTS.md to pointer + CI contract instead of 40 lines of prose.
5. Keep `bv`/graph triage as the reason to stay. If GitHub Issues is later adopted, do not mirror mutable state in both systems.

**Q4. Exit criteria — [satisfied-conditional: wrapper metrics instrumented from rollout]**

Track for one month: double claims, push retries/failures, rebuild failures, duplicate-id CI hits, recovery-file count, data-loss incidents, time-to-claim, and share of `main` commits touching `issues.jsonl`.

Reconsider if: any confirmed bead loss on 0.7.6; more than two double-claim incidents; rebuild failures above 5% of worktree bootstraps; more than 10% of queue pushes needing retry or median claim latency above five minutes; another breaking schema migration blocking upgrades for over a week; or graph queries going unused for two weeks. In those cases move coordination to GitHub Issues and keep beads only as a read-only local projection, or drop to markdown if graph triage proves unnecessary.

</details>

### Narrowed follow-up

<details>
<summary>Follow-up prompt</summary>

ROUNDTABLE follow-up (narrowed): beads-rust as the homelab's agent task tracker

You answered round 1 of this discussion. All five voices recommended: stay on beads_rust v0.7.x; move every repo's queue to a dedicated `beads-queue` branch; make the `beads-q` wrapper the only writer; ban `.beads/` changes from feature PRs; pin and upgrade deliberately; shrink AGENTS.md. GitHub Issues was everyone's fallback.

The discussion leader checked facts that round 1 disagreed on or assumed (2026-11-25):

F1. `beads-q` (unified-nix-configuration `pkgs/beads-queue.sh`) already implements the loop: fetch, hard-reset a dedicated queue worktree to the remote branch, rebuild the DB, run the command, export, commit, push without force; on rejection, retry from the new tip (bounded retries); only the output of the attempt that landed is shown. `update --claim` fails with CLAIM_CONFLICT if the bead is already claimed in the rebuilt DB. So a claim that goes through `beads-q` is re-validated against the latest tip and published by a fast-forward push. Not yet tested: a deliberate two-client race.

F2. The original beads (`gastownhall/beads`, Go) is no longer JSONL-in-git: its README says it is "powered by Dolt" (version-controlled SQL, cell-level merge, `bd dolt push/pull` to Dolt remotes) and uses hash-based ids (`bd-a1b2`) to prevent merge collisions. Round 1 voices who said it shares beads_rust's model were wrong; Codex was right.

F3. beads_rust v0.7.6 still mints integer comment ids and `<parent>.N` child ids from a local counter. Tested on a copy of the queue: a comment-id collision that merges cleanly in git is renumbered on import and both comments kept; child-id collisions on the same parent usually conflict in git.

F4. GitHub has a REST API for issue dependencies (blocked-by/blocking) and sub-issues; assignment is not compare-and-swap.

Answer only these, under 500 words, marking each with `[satisfied]`, `[satisfied-conditional: X]` or `[needs more evidence: X]`:

N1. Given F1, are claims through `beads-q` atomic enough, and what single test would prove it? Does F4 change your view of GitHub Issues' claim story?

N2. Given F2, does Dolt-backed Go beads with hash ids beat "beads_rust + queue branch" for this homelab (one operator, about three repos, a handful of parallel agents, Nix-packaged tools)? Consider running a Dolt remote vs a git branch.

N3. Round 1 split on two details. (i) Keep the duplicate-id CI check permanently, only on the queue branch, or retire it after a clean month? (ii) One voice proposed a CI rule requiring each feature PR's first commit to claim its bead; others ban `.beads/` from feature PRs. Which rule, and how does a feature PR then reference its bead?

</details>

<details>
<summary>Codex</summary>

**N1. [satisfied-conditional: a deliberate two-client race passes]** `beads-q` provides sufficient atomicity for claims if every writer uses it. The fast-forward push is the point at which a claim takes effect. A losing push forces the wrapper to rebuild from the new tip and revalidate the claim. In a disposable queue, give two clients separate worktrees and have them claim the same unclaimed bead as different assignees. Hold both immediately before their first push so both attempts are based on the same tip, then release them. Require exactly one success, `CLAIM_CONFLICT` from the losing client after retry, and the winner as the sole assignee in a fresh import from the remote. F4 improves GitHub Issues’ dependency and hierarchy support. Its assignment API still lacks compare-and-swap, so the claim assessment stands.

**N2. [satisfied]** Keep beads_rust and the queue branch. Dolt’s cell-level merge and hash-based IDs address merge friction and ID collisions. With one operator, three repos, and a handful of parallel agents, the existing wrapper already serializes writes using the Git remote each repo has. A Dolt remote adds provisioning, credentials, and recovery procedures. Nix packaging helps with client version consistency. Hash-based IDs also leave the same-bead claim race to the tracker’s claim semantics.

**N3. [satisfied]** Keep the duplicate-ID check permanently and scope it to the queue branch. Check the exported data before import, since import can silently renumber duplicate comment IDs. A clean month shows the normal write path is working, while the check still catches regressions or writes that bypass the wrapper. Ban `.beads/` changes in feature PRs with a path check. Claim through `beads-q` before starting work, then include the repository-scoped bead ID in the PR body, for example `Bead: my-repo-abc`. If CI needs to verify the reference, resolve that ID against `beads-queue`.

</details>

<details>
<summary>Gemini (agy)</summary>

### N1. Atomicity & GitHub Issues Claim Story
`[satisfied-conditional: concurrent race verification]`

**Atomicity**: Yes. Git non-force pushes act as a distributed Compare-And-Swap (CAS) over the branch ref. Combined with `beads-q`'s post-fetch DB rebuild and `CLAIM_CONFLICT` check, concurrent claims are strictly serialized: the losing push is rejected, retries against the winner's new tip, and fails fast on `CLAIM_CONFLICT`.

**The Single Test**:
Run a parallel race against an unclaimed bead:
```bash
beads-q update --claim bd-42 & beads-q update --claim bd-42 & wait
```
*Pass criteria*: Exactly one process exits `0` with a pushed commit; the second exits non-zero with `CLAIM_CONFLICT`; `git log` on `beads-queue` shows exactly one claim commit.

**GitHub Issues Impact**: F4 confirms `beads-q` is superior for claiming. GitHub's REST API lacks CAS assignment—simultaneous assignment requests result in last-write-wins or merged assignee arrays without conflict errors, creating split-brain agent execution. Git ref updates provide the true CAS primitive GitHub lacks.

---

### N2. Dolt-backed Go Beads vs. beads_rust + Queue Branch
`[satisfied]`

**Verdict**: Dolt does not beat `beads_rust + queue branch` for this homelab.

- **Operational Overhead**: A Git branch leverages your existing Git server (Forgejo/GitHub) with zero new daemons. Dolt introduces another stateful server, backup target, and access-control plane for only ~3 repos.
- **Nix Ergonomics**: `beads_rust` and `beads-q` are already integrated in `unified-nix-configuration`. Packaging Go beads alongside the Dolt runtime adds packaging surface for negligible homelab gain.
- **Problem Mismatch**: Dolt and hash IDs (`bd-a1b2`) solve multi-master asynchronous merges. Because `beads-q` linearizes writes via fetch-retry fast-forward pushes, merge collisions are already eliminated at the Git transport layer. Dolt's cell-level merge adds complexity without solving an active problem.

---

### N3. CI Rules & PR Bead References
`[satisfied]`

**(i) Duplicate-ID CI Check**:
Keep it **permanently**, but **only on the `beads-queue` branch**. 
Running a duplicate-ID scan on a small JSONL file takes milliseconds in CI. Retiring it yields negligible speedup while removing a vital safety net against emergency manual edits or wrapper bypasses.

**(ii) Policy & Referencing**:
**Ban `.beads/` completely from feature PRs.** Coupling queue state to feature code re-introduces the exact merge conflicts the queue branch was designed to eliminate.

**How Feature PRs Reference Beads**:
1. **Branch Naming**: `agent/<bead-id>-<slug>` (e.g., `agent/bd-102-fix-auth`).
2. **Commit / PR Metadata**: Include trailers in commit messages and PR bodies:
   ```text
   Fix authentication timeout

   Bead: bd-102
   ```
3. **Lifecycle Management**: The agent claims out-of-band via `beads-q update --claim <id>` before pushing the branch. Upon merge, either the coordinating agent or a post-merge CI automation invokes `beads-q close <id>` directly on the `beads-queue` branch.

</details>

<details>
<summary>Claude (claude -p)</summary>

**N1. Atomicity of `beads-q` claims: `[satisfied-conditional: the race test below passes and the branch is protected against force-push]`**

The loop in F1 is atomic in the way that counts. A push without force is a compare-and-swap on the queue branch: the server accepts it only if the branch hasn't moved since the client fetched it. Each try re-checks the claim against a freshly rebuilt database, so two clients can't both get a claim in.

This holds only if:
- every writer goes through `beads-q`;
- force-push to `beads-queue` is blocked on the server;
- agents start work only after `beads-q` exits 0;
- claims from crashed agents get a timeout or a manual release step.

**The test:** make K separate clones (try K=2, 4 and 8). Have them all run `beads-q update --claim <same-id>` at the same moment, synchronised by a barrier. Repeat about 100 times. Pass means:
- exactly one client exits 0 and the rest get CLAIM_CONFLICT;
- `beads-queue` gains exactly one claim commit per round;
- the history is linear;
- the JSONL rebuilds into the same database.

Put a deliberate retry in the mix (a hook that rejects the first push) so the retry path is tested too.

**GitHub, given F4:** the native dependency and sub-issue API makes GitHub a stronger fallback. Assignment still isn't a safe claim. A safe claim can use the same idea, though: creating a git ref through the API fails if the ref already exists. So "create `refs/heads/claim/<issue#>`" is an atomic claim, and the assignee field is just for display. GitHub stays the fallback, with that rule.

**N2. Dolt-backed Go beads: `[satisfied: stay on beads_rust + queue branch]`**

Hash ids fix the problem in F3, but F3 mostly doesn't apply here. `beads-q` rebuilds from the latest tip before every write, so local counters always start from current state. Collisions only happen when someone bypasses `beads-q`, and the permanent CI check (N3) catches that.

Dolt would add costs:
- a second store with its own remote: DoltHub, or a self-hosted remotesapi or sql-server to run, back up and secure;
- a second sync tool next to git (`bd dolt push/pull`);
- a new tool to pin in Nix;
- queue history moves out of the repo, where it can no longer be read and reverted with ordinary git.

For one operator with about three repos, a git branch is already on the remote and already backed up. Revisit Dolt if:
- the race test fails in a way you can't fix;
- agents need to write offline and merge later;
- the number of repos or agents grows a lot.

**N3. CI rules: `[satisfied]`**

**(i) Keep the duplicate-id check permanently.** Run it on every push to `beads-queue`, and on feature PRs as part of the `.beads/` ban. It costs seconds. It is the only thing that catches writes that bypass `beads-q`, and regressions after a beads_rust upgrade. A clean month only shows that nothing bypassed it that month, not that nothing can.

**(ii) Ban `.beads/` changes from feature PRs.** A "claim in the first commit" rule would bring queue writes back onto feature branches, where they merge late and collide, which is the problem the queue branch exists to solve. The claim already happened on `beads-queue` through `beads-q`, before the branch was cut. A feature PR refers to its bead by:
- branch name `bead/<id>-<slug>`, plus a `Bead: <id>` trailer in the PR body or commits;
- a CI check that reads `origin/beads-queue` and fails if the bead doesn't exist or isn't `in_progress`;
- a post-merge job (or the agent) that closes the bead through `beads-q`.

That keeps the queue branch as the only record of claim state, and links each PR to its bead by reference instead of by editing `.beads/`.

</details>

<details>
<summary>Copilot (copilot -p)</summary>

N1. [satisfied] `beads-q`'s loop (fetch → hard-reset → rebuild DB → run → export → commit → push-no-force → retry-on-reject-from-new-tip) gives claims the same atomicity as any git-branch-as-lock design: the push is the compare-and-swap, and `CLAIM_CONFLICT` on rebuild means a losing client never even produces a commit worth pushing. That's "atomic enough" for one operator with a handful of agents — correctness, not throughput, is the goal, and serialized pushes make throughput irrelevant. The single test that would prove it: launch two `beads-q update --claim` invocations against the *same starting tip*, deliberately staggered so both pass their local CLAIM_CONFLICT check before either pushes (e.g. pause one after rebuild, before commit, via a test hook or a tiny sleep patched into the script), and confirm exactly one push lands while the other is forced to retry and re-fails claim against the new tip. Until that race is run, this is inference from the code, not demonstrated — so call it [satisfied-conditional: the staggered double-claim test above is run and shows exactly one winner].

F4 doesn't change the GitHub Issues view much: assignment being non-CAS was already the core objection in round 1, and F4 confirms it — the dependency/sub-issue API is orthogonal to the race condition. GitHub Issues remains the fallback for structure and portability, not for atomic claiming.

N2. [satisfied-conditional: operator is willing to run and back up a Dolt remote server]. For one operator/three repos/a handful of agents, Dolt's hash ids remove the comment/child-id renumbering issue in F3 outright, which is a real correctness edge beads_rust doesn't have. But that benefit only materializes if there's an actual Dolt remote (Dolt Hub, DoltLab, or self-hosted `dolt sql-server` exposing a remote) — without one, "Dolt-backed" degrades to a local SQL file with no better conflict story than a git branch, plus added Nix-packaging and backup burden for a second storage engine. Given the stated scale, a git branch is already sufficient infra (it's just git), it's already Nix-packaged, and the main class of defect it has (F3's integer ids) only bites on true concurrent writes to the same parent, which is rare at "a handful of agents." Net: stay on beads_rust + queue branch unless the operator starts seeing real child-id conflicts in practice; re-evaluate Dolt then, not now.

N3. (i) [satisfied]: keep the duplicate-id CI check permanently, scoped only to the queue branch (it's cheap, catches a known failure mode from F3, and "clean month" retirement is a trap — the whole point of F3 is the collision is rare, so a quiet month proves nothing about whether it's fixed).

(ii) [satisfied-conditional: the repo already enforces squash-merge or a single-commit-per-PR convention]: prefer the "first commit claims the bead" rule over banning `.beads/` entirely, but only where commit history is clean enough that "first commit" is unambiguous — otherwise it degenerates to the same ban-by-default outcome with extra ceremony. A feature PR then references its bead not via a `.beads/` diff but via the bead id in the PR title/description (e.g. `Closes bd-xxxx`) or a commit trailer, keeping `.beads/` mutation confined to `beads-q` on the queue branch while still giving reviewers and CI a queryable link between PR and bead.

</details>

<details>
<summary>DeepSeek (API)</summary>

**N1. [satisfied-conditional: the two-client race test passes]** F1's loop is a genuine compare-and-swap: rebuild from tip → `update --claim` (CLAIM_CONFLICT if taken) → export → non-force push → retry from new tip on rejection. The only unproven link is that a losing client's retry re-reads the winner's claim and fails cleanly rather than double-claiming. Single test: two worktrees, both `beads-q update <id> --claim` fired simultaneously (or with a hook that pauses client A between rebuild and push); assert exactly one succeeds, the loser exits CLAIM_CONFLICT after retry, and the queue branch has one claim. F4 doesn't rescue GitHub Issues: REST dependency/sub-issue endpoints are fine for structure, but assignment is last-write-wins, so two agents can both "own" an issue. GitHub's claim story stays weaker; it remains the fallback, not the target.

**N2. [satisfied-conditional: you accept a second remote and Dolt's Nix packaging]** For one operator, three repos, a handful of agents: no. Dolt buys cell-level merge and hash ids — real wins — but costs a Dolt remote (server or DoltHub) alongside git, a second sync protocol (`bd dolt push/pull`), and Nix-packaging a Go+Dolt binary versus the already-packaged beads_rust. The queue branch already gives you serialized writes and a fast-forward CAS; F3's collision classes are handled by renumber-on-import (comments) and rare git conflicts (child ids), both tolerable at this scale. Revisit if agent count or merge friction grows, or if beads_rust's integer ids start biting in practice.

**N3. [satisfied]**
(i) Keep the duplicate-id CI check permanently, scoped to the queue branch. It's cheap, and F3 shows collisions are silent-but-renumbering on comments — a permanent guard beats a one-month trial you'll forget to re-arm.
(ii) Ban `.beads/` from feature PRs; `beads-q` is the only writer (round 1's consensus). Don't require a claim commit in the PR — that reintroduces the second writer. Instead, the feature PR references its bead by id in the title or body (`beads: <id>`), and CI checks that id exists and is claimed on the queue branch. Claiming happens via `beads-q` before the PR opens; the PR is read-only w.r.t. `.beads/`.

</details>
