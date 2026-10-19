# P1 mapping workflow and persistence

**Pre-MVP owner storage decision:** mapping uses only current experimental schema **8**. No automatic mapping migrations, new `.pN-backup`, resets or deletions; old/corrupt files fail closed and all existing files are preserved. Earlier mapping-schema descriptions below are historical, not supported compatibility. Atomic current saves/`.previous`, integrity, external-change guards and immutable evidence/history remain. The independent original-measurement journal keeps its deployed compatibility. See [current storage/recovery](p4-1-photos.md) and [AGENTS.md](../AGENTS.md).

**P3.1 update:** [Integrated measurements](p3-measurements.md) supersedes historical standalone-only measurement navigation, empty measurement links and schema-1/2-only statements. Mapping now saves point-owned originals atomically in schema 3; the existing DXF contract is unchanged.

**P2 update:** [P2 mapping and DXF contract](p2-dxf.md) supersedes historical P1 statements about optional horizon elevations, mandatory per-point coordinate strings, absent plans and schema 1. P2 adds nominal Z provenance and immutable managed DXF revisions on the same graph; orientation/measurement conventions are unchanged.

## Implemented workflow

The app opens on **Картирование**. Its fixed context panel is Project → Horizon → Excavation; only the draft below it scrolls. Management buttons create/rename projects, create/edit horizons (optional elevation and explicit datum), and create/rename excavations with one or more horizon UUIDs. Creation does not implicitly select an item or bypass draft protection. Projects have independent horizons, excavation identities and observations. The selected context is persisted in the same commit stream as the journal.

Mapping captures individual points; no 5–10 m interval is required. Future intervals can reference these point IDs without duplicating evidence. Input accepts nonnegative plain meters with decimal comma/dot, or explicit **kilometer+meter** notation: `ПК 0+005` = 5 m, `ПК 1+005` = 1005 m. The suffix requires exactly three integer digits (optional decimal fraction); `1+05` is rejected. This is an explicit P1 input convention, not a claim that all survey pickets are 1000 m. Original text and numeric meters are retained. Chainage origin/direction is optional text, explicitly `unknown` if absent; no alignment, coordinates or surveyed position is inferred.

Coordinates are optional independent X/Y/Z in meters. A partial coordinate is allowed; unknown components remain nil. Coordinate entry requires explicit CRS, axis/vertical convention and provenance/limitations (the user may explicitly state unknown). Source is always manual in P1. Z is never inferred from a horizon name/elevation. DXF, plan selection and underground GPS are unavailable and labeled accordingly.

New observations have current field time at save unless the user changes the date picker. `observedAt` is a UTC instant, with captured timezone identifier and UTC offset for that instant, independent of `createdAt`/`updatedAt`. The original timezone offset formats historical records even if device timezone changes. Observation date overrides reset after success; historical observations never receive a new date on load. P1 observations are immutable and view-only; editing/revision workflows are deferred, rather than modifying originals through the new-observation form. Renaming context entities updates their displayed labels; UUID links remain stable. Historical parent-label revisions are future work.

Saving validates a complete context, picket and any coordinate metadata, then atomically commits the complete graph. Only confirmed success resets all implemented draft fields (picket, chainage description, date override, coordinates/metadata, notes), retaining all three selectors. No rating/attachment/measurement staging exists yet. Validation/I/O failure leaves the draft/context untouched. A dirty draft, including a date-only override or coordinate metadata, blocks project/horizon/excavation switches behind an explicit discard/cancel dialog. Management and navigation do not clear it. Drafts remain in memory across tabs/backgrounding; they are not persisted across process termination and are never autosaved as completed observations.

## Navigation and scope

Exactly three primary tabs: **Картирование / План / Клинья**. Plan and wedge tabs explicitly explain their unavailable state. Mapping's journal button opens the selected project's observations, sorted by observed date descending or numeric chainage ascending, with read-only details. Secondary **Сервисы** navigation exposes independent sensor/manual measurement, the explicitly unassigned Phase 1/2 journal, and settings/legacy CSV export. Sensors run only while the measurement screen is visible in the foreground; HOLD/manual mode still stop acquisition. Compact forms and reusable components are shared; the capture column is bounded on wider windows. A native iPad sidebar/split workflow remains future work, and no iPad target is added.

Joint sets J1–J5, Q, RMR, faults and photos are disabled placeholders. Capturing/linking original orientation measurements inside mapping is explicitly deferred to **Issue #8**. Independent measurement remains operational with original provenance; no dummy attachment/save operation is supplied. Ratings, mechanical/wedge equations, full photos, DXF, LiDAR and XLSX are not implemented.

## Storage decision

P1 uses a dependency-free **versioned JSON aggregate repository** (`MappingStore` / `FileMappingStore`), owned serially on the main actor, at Application Support/FieldForge/**mapping-v1.json**. It contains all projects, horizons, multi-horizon excavations, reserved horizon-to-plan-reference metadata, immutable point observations and the selected context. This is the single project graph for future Mapping/Plan/Wedge consumers; modules must query it by UUID rather than create copies.

SQLite was recommended for the eventual large relational/attachment workload. P1 deliberately retains the existing small-journal atomic JSON approach: a single validated aggregate gives all-or-nothing relationship/context commits without introducing an incomplete legacy migration alongside new UI. There is no cross-file transaction with the protected legacy journal because P1 never mutates it or links records across stores. Before Issue #8 or large attachment/plan workloads, qualify a transactional SQLite migration with full graph and original-measurement round-trip fixtures. Whole-file main-actor JSON is suitable only for the current small foundation; it has no indexed queries or multi-process lock.

Every commit validates schema version, UUID uniqueness within entity types, project ownership, horizon/excavation membership, selected context, picket value, finite coordinates/timestamps and coordinate metadata. Observations cannot be removed or altered by the repository. The unsupported `measurementIDs` field must remain empty until a verified link repository exists. `MappingPlanReference` reserves many plan versions per horizon via stable UUIDs; importing/rendering/resolving attachment bytes is deferred.

Save sequence:

1. Load and validate source; unknown/corrupt schemas block writes (never fall back to an empty writable store).
2. Validate the candidate graph and ensure every prior original observation remains byte-value-equivalent in decoded form.
3. Compare source bytes to the last loaded/saved bytes; reject external modifications.
4. Encode with full Double precision and validate exact round-trip equality.
5. Atomically preserve the previous readable bytes as **mapping-v1.json.previous**. A backup failure prevents commit.
6. Recheck source and atomically replace the active file. Publish/reset only after success.

The `.previous` file is a rolling previous snapshot, not a complete long-term backup/export facility. Failed load never automatically restores it (that could discard newer observations). Preserve both files, validate a staging repair, then explicitly restore. Foundation atomic replacement is not a claim of guaranteed power-loss durability; device disk-full/power-loss validation remains outstanding. Multi-process writers are not supported.

## Legacy safety

Existing **measurements-v1.json** and **measurements-v1.json.phase1-backup** keep their paths, schema and original values; opening/using mapping does not import, rewrite, assign or delete them. The existing explicit v1→v2 migration runs only through `FileMeasurementStore`; its validation/backup/failure behavior remains. The legacy inbox is visibly unassigned. Bundle ID stays **com.tinuvael.FieldForge**, and no physical iPhone install/uninstall was performed.

Local Xcode Team settings live in ignored **Config/LocalSigning.xcconfig**, included optionally by checked-in **Config/Signing.xcconfig**. Generator output is deterministic and contains no personal Team. The pre-existing local Xcode project/patch were preserved outside the repository before regeneration.

## Platform regression discovered during verification

The literal Phase 1 Linux fixture stores a 45° dip; Darwin libm recomputes it as 44.99999999999999°. Previously `Measurement.isSavable` required exact recomputation equality, rejecting genuine legacy records. Sensor validation now permits at most 32 ULPs at `max(1, |stored|, |expected|)` per numerical orientation component; status/nil/provenance/quality rules remain exact. Original values are never overwritten or rounded. Geometry algorithms are unchanged. Regression tests reject 1e-8 perturbations and changed status. CSV tests compare parsed engineering values instead of requiring the platform to stringify a recomputed angle as exactly `45.0`.

See [P1 verification](p1-verification.md) for executed checks and remaining limitations.
