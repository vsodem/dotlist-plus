# iCloud sync implementation plan

Goal: synchronize one personal list per iCloud account while preserving offline work, recovery copies, and version-2 backups.

Design brief: the user's “Add iCloud sync with replaceable storage” request. Behavior and acceptance checks live in docs/APP_RULES.md.

Architecture: DotListCore owns async provider-neutral contracts, durable account state, three-way merging, and a serialized coordinator. DotListStorage owns JSON files and migration. The Apple app owns CKSyncEngine and injects both adapters at startup. BackupCodec handles only portable backup data.

1. Add neutral contracts and merge tests. Merge projects by ID and task fields independently except relationships, which form one unit. Merge order with baseline-relative constraints, and report incompatible order. Preserve both input snapshots on conflicts. Validate before saving or uploading. Divergent review progress resets with a notice.
2. Extract BackupCodec and implement atomic JSON storage plus in-memory storage contracts. Persist all accounts, baseline, pending state, conflict inputs, and opaque checkpoints in one envelope. Migrate state-v2.json without deleting it. Recovery copies precede replacement.
3. Implement and test coordinator serialization, offline changes, first sync, conditional writes, retry after remote success/local failure, account separation, import, erase, and restart. First account adopts unbound local data once; subsequent accounts never adopt another account's data. Unknown account status does not switch accounts.
4. Implement CloudKit snapshot adapter using CKSyncEngine. Keep record metadata and asset encoding private. Use opaque account IDs and revisions. Fetch before conditional publication; surface conflicts. Check account before and after operations. Return checkpoints only with the operation outcome.
5. Inject dependencies at app startup. Make UI actions await durable storage before dismissing editors. Settings shows sync status, retry, and explicit conflict choices. Import and erase confirmations describe effects on other devices.
6. Preserve capabilities and signing configuration in generator. Run swift test, unsigned macOS and iOS simulator builds, generator reproducibility, and independent review. Attempt signed provisioning only with configured team. Record live-device verification as blocked if identities/devices are unavailable.
7. Review explicit file diff, commit, fetch, push HEAD to codex/swift, and compare with ls-remote. Leave .github/workflows/playwright.yml untouched.

Review focus: suspension during account changes; interrupted local writes after successful upload; unchanged remote replay after conflict choices; structural merges invalidating review; lost notifications during an in-flight sync.


Implementation decisions and verification:
- Stayed on the requested codex/swift checkout; no worktree or branch switch needed. The unrelated Playwright workflow remains untouched.
- CKSyncEngine handles incoming changes and checkpoint state. Outgoing writes use explicit conditional CloudKit saves so stale engine queues cannot replay.
- Interrupted uploads with changed remote contents require a complete-list choice; this prevents deletion resurrection without unbounded server history.
- Inactive accounts retain their lists. The first account adopts unbound data only once; later local-only data requires explicit export/import to transfer.
- Independent review caught record-order convergence, ambiguous upload acknowledgement, conflict retention, and stale-account/state UI actions. Regression tests cover the fixes.
- Core tests run with in-memory fakes; shared storage contracts also exercise the JSON implementation. The fake remote contract cannot verify live CloudKit behavior.
- Unsigned macOS and iOS simulator builds succeeded. Signed iOS build is blocked by the missing com.vsodem.DotList development profile and zero valid signing identities. Registration/schema deployment and two-device verification remain outstanding.
