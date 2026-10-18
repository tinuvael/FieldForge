# P3.2b — point/interval rock-mass assessments

## Qualified reference and edition

Barton Q uses **NGI, April 2025, _Using the Q-system: Rock mass classification and support design_**, not an unspecified original/2015 table. [Official handbook](https://www.ngi.no/globalassets/bilder/forskning-og-radgivning/bygg-og-anlegg/q-handbook_2025_english_final.pdf), retrieved 2026-10-18, PDF SHA-256 `30477f4b8f1b026a637343807d654d74e45ebdeb4381b68d88cd7429bc37ce57`. Publication date was checked on PDF page 2, preface on page 4. Relevant printed pages: formula p.6; selection guidance pp.9–27; tables 3-1…3-7; appendix tables 1–6 pp.53–57 (the separate stress-ratio table 3-7 is on p.25); quality classes in Figure 4-1 p.31 (PDF page 35). Appendix tables and the class chart were rendered and visually checked as well as read as text. The appendix numbering jumps from 6 to 8; tables 8–9 concern support design and are excluded from this feature.

Implementation identity: `NGI-Q-2025-04/FieldForge-1`. The identity freezes tables, conventions, validation and calculation; it is not a claim that NGI certified this implementation. Any later methodology change needs a new implementation version, new acceptance cases and explicit handling of historical snapshots.

## Q selection contract

All Q factors are dimensionless except original RQD, entered as a percentage 0–100. Decimal comma/dot and original text are retained. Empty values remain missing. Fixed table rows populate their published value only after explicit row selection. Ranges start blank; the engineer must enter a finite value inside the selected row and provide its evidence/rationale. Manual edits of fixed rows must equal the published value. No arbitrary coefficient, automatic text interpretation, automatic joint-set counting, midpoint or default factor is used.

The Russian lists in `QMethod.rows` provide concise selection descriptions, including the following numerical acceptance sheet. Use the original handbook for full engineering interpretation; the app stores separate field descriptions/evidence and the selected row, rather than replacing geological observations with numbers.

| Parameter | Verified appendix row IDs and accepted base values |
| --- | --- |
| Jn, table 2 | A 0.5–1; B 2; C 3; D 4; E 6; F 9; G 12; H 15; J 20 |
| Jr, table 3 | A 4; B 3; C 2; D 1.5; E 1.5; F 1; G 0.5; H 1 |
| Ja, table 4 | A 0.75; B 1; C 2; D 3; E 4; F 4; G 6; H 8; J 8–12; K 6; L 8; M 8–12; N 10; O 13; P 13–20 |
| Jw, table 5 | A 1; B 0.66; C 0.5; D 0.33; E 0.1–0.2; F 0.05–0.1 |
| SRF, table 6 | A 10; B 7.5; C 5; D 5; E 2.5; F 2.5; G 1; H 0.5–2 / 2–5; J 5–50; K 50–200; L 200–400; M 5–10; N 10–20; O 5–10; P 10–15 |

### Conditions and explicit special cases

- **RQD:** §§3.2–3.2.4, table 3-1 / appendix 1. Keep the original measured or reported 0–100%; use `max(originalRQD, 10)` only in Q. Preserve whether it is a core measurement, a field estimate or an external report/manual entry, plus evidence. Original RQD is not rewritten, rounded to 5% or changed in RMR. No automatic joint-volume/RQD estimation is implemented. Foliation, blast fractures, weak/soil-like material, drying of cores and healed/mineral-filled joints require the engineer's interpretation and field notes; none is inferred from J1–J5 or free text.
- **Jn:** only co-located, block-forming systems should be assessed (§3.3); random joints and joint extent matter. Select ordinary, intersection or portal explicitly. Use base Jn ×1, ×3 or ×2 respectively; do not stack portal/intersection multipliers. Their spatial extent depends on excavation dimensions/rock quality and must be judged by the engineer. Base Jn and the effective denominator remain distinct. Counts of saved readings/representative J1–J5 never set Jn.
- **Jr and Ja:** §§3.4–3.5. The engineer evaluates all relevant systems and selects the system most adverse for shear/stability, recording its identity, potential sliding direction and rationale. Roughness is directional and scale/block-size dependent; the app does not infer the governing system. Select contact `a` (wall contact), `b` (contact before 10 cm shear), or `c` (no contact during shear). Ja A–E requires `a`, F–J requires `b`, K–P requires `c`. Jr A–G applies to `a/b`; Jr H =1 applies to `c`. This contact compatibility is checked. The <5 mm conditions in Ja G/H/J are retained; filling thickness alone does not establish contact because waviness/roughness matters. Swelling fraction informs Ja J/M/P ranges; no mineral or percentage classifier is implemented.
- **Jr +1:** explicit choices for table-3 note i (relevant mean spacing >3 m, dependent on excavation size), or §3.4.3 (few exposed joints). The spacing option requires a finite mean >3 m. Either requires written evidence including excavation geometry/applicability. No +1 for no-contact/H. Jr G's lineations must align with the expected sliding direction; selecting that descriptive row is the assessor's declaration, not an automatic directional test. Weak unjointed/soil-like material needs separate assessment under §3.4.3; the app does not invent a joint or infer coefficients from UCS.
- **Jw:** assess observed inflow/pressure, filling washout and change over time (§3.6). E/F are different temporal conditions even though they share 0.1. C–F are rough estimates. Drainage/grouting requires reassessment of the selected row and written evidence; no unsupported interpolation outside a published row is accepted. Ice effects are not included. Seasonal/delayed changes must be documented.
- **SRF:** choose the stress regime before a value. A–E are weak/loose zones (C depth ≤50 m; E >50 m), F/G low/favourable stresses, H/J/K/L mainly massive competent rock under high stresses, M/N plastic squeezing, O/P chemical swelling. H's two published intervals are explicit `H` / `H-star` choices; neither is silently selected. The app does not assign one interval from an inferred favourable/unfavourable label: the engineer must apply §3.7.3, consider stress orientation/anisotropy and document the range selection. J occurs >1 hour after excavation, K after minutes, L immediately; time and intensity matter. All range values require written rationale. Squeezing/swelling need the relevant investigation/literature cited by NGI, not an automatic decision from stress or groundwater text.
- **SRF corrections:** table-6 note i explicitly permits 25–50% reduction for A–E zones that influence but do not intersect the opening: effective SRF = base ×(1−reduction/100). F note ii permits SRF=5 when crown cover is less than span. These are separate explicit modes, require written geometric justification and cannot be combined. No correction is inferred from horizon elevation or coordinates.
- Table 3-7 stress/strength ratios (mainly RQD/Jn >20) and its anisotropic stress-field UCS reductions are guidance for the engineer, **not computed** by this implementation. No automatic UCS/stress-ratio→SRF conversion, field-estimate calibration, narrow weakness-zone averaging, Q′/Qbase, wall-support scaling, ESR or support design is implemented.

Missing source, context/contact, parameter, range rationale or correction prerequisite yields `Недостаточно данных для расчёта` with the missing list. These incomplete assessments may be saved explicitly with their status and missing-data reason. Invalid numbers, out-of-row values or incompatible populated conditions prevent point save and retain the entire draft. Zero RQD is valid; zero Jn/Jr/Ja/Jw/SRF is invalid. All three effective denominators must be >0. Evaluation stores unrounded values:

`Q = (calculationRQD / effectiveJn) × (effectiveJr / Ja) × (Jw / effectiveSRF)`.

### Classes in this edition

Figure 4-1 in **2025 has seven classes**, with A (very good) covering the upper plotted range; do not substitute a nine-class scale from another edition. The chart shares boundary lines. This implementation explicitly assigns an exact transition to the higher-quality interval without rounding first:

| Class | Russian label | Q interval |
| --- | --- | --- |
| G | Исключительно плохой | [0.001, 0.01) |
| F | Крайне плохой | [0.01, 0.1) |
| E | Очень плохой | [0.1, 1) |
| D | Плохой | [1, 4) |
| C | Средний | [4, 10) |
| B | Хороший | [10, 40) |
| A | Очень хороший | [40, 1000] |

Outside the plotted 0.001–1000 scale, retain the numerical Q and label the class unavailable/outside the published scale. Do not clamp Q, extrapolate a class or label a mass stable/unstable. Display Q with approximately six significant digits (`≈`), retain full floating-point precision, and show the calculation factors and original/used RQD separately. Display resolution is not measurement accuracy or engineering certainty. No support recommendation is shown.

## RMR89 verification gate

Target: **Z.T. Bieniawski (1989), _Engineering Rock Mass Classifications_, Wiley, ISBN 0-471-60172-1**, specifically RMR89; implementation identity `Bieniawski-RMR89/input-only-v1`.

The [USDA/Tonto National Forest bibliographic entry](https://www.resolutionmineeis.us/documents/bieniawski-1989) explicitly identifies its PDF as **COVER ONLY**. The [Google Books bibliographic preview](https://books.google.com/books/about/Engineering_Rock_Mass_Classifications.html?id=pejDUvjwPdMC) establishes the Wiley book identity, but did not provide the complete original tables for verification. A direct publisher-page fetch was unavailable. Search located secondary reproductions, including Hoek/teaching material, but these were not used as a substitute for checking the complete original RMR89 tables and special cases. Therefore **no numerical RMR table, interpolation, orientation adjustment or class is implemented**. No approximate/combined RMR76/89/14 is produced. The status is always `Расчёт не реализован — требуется проверка методики`, including when every input has been entered. Both basic RMR and orientation-adjusted RMR explicitly remain uncalculated.

The form retains strength test type (UCS or Is(50)), original MPa text and laboratory/source/applicability notes; original RQD and evidence; spacing in m; persistence in m, aperture in mm, roughness, filling type/thickness/properties and wall weathering; groundwater description and optional l/min per 10 m and water-pressure/major-principal-stress ratio; engineering application (tunnels/mines, foundations, slopes) and orientation/drive/north description; source, assessor and missing-data reason. It does not convert point-load values to UCS or apply Q's RQD floor. RMR inputs are assessment snapshots, not duplicate original fracture observations. To enable numerical RMR later, first qualify all original rating/condition/groundwater/orientation tables, boundary ties and special cases for the exact edition and add independent acceptance cases.

## Independent acceptance examples

These are **hand-calculated rational-arithmetic fixtures**, not claims of observed site conditions, not generated by the calculator under test, and not a second independent geotechnical peer review. Geological suitability of the selected categories remains the assessor's responsibility.

| Case | Original inputs / decisions | Independent arithmetic / expected result |
| --- | --- | --- |
| Ordinary | RQD 80, Jn F=9, Jr B=3, Ja C=2, Jw A=1, SRF G=1; wall contact | `(80/9)×(3/2)×1 = 40/3 = 13.333333…`, B good |
| Water/zone | RQD 60, Jn D=4, Jr E=1.5, Ja E=4, Jw B=.66, SRF C=5; wall contact | `15×(3/8)×(33/250) = 297/400 = .7425`, E very poor |
| Floor | Original RQD 0, .125, 5, just below 10, or 10; otherwise ordinary inputs above | calculation RQD 10; `(10/9)×(3/2) = 5/3`, D poor; original text unchanged |
| Intersection, thick filling | Original RQD 5, Jn J=20 ×3, Jr H=1, Ja P=20, Jw F=.05, SRF L=400; no contact | `(10/60)×(1/20)×(.05/400) = 1/960000`, outside class chart |
| Portal | Ordinary example with Jn ×2 | effective Jn 18, Q `20/3` |
| Roughness correction | Ordinary example with justified Jr +1 and mean spacing >3 m | effective Jr 4, Q `160/9` |
| Adjacent zone | Base SRF A=10, justified reduction 25% / 50% | effective SRF `15/2` / `5` |
| Shallow roof | Base SRF F=2.5; justified cover <span | effective SRF `5` |

Tests also verify endpoints and next representable values around all six class transitions, all table-value endpoints, zero/missing/nonfinite/out-of-range values, a/b/c contact combinations, correction misuse, no auto grouping, incomplete Q/RMR persistence, full raw precision, complete/failed save/reset, exact legacy backups, blocked corrupted/stale-result/unknown-method files, append-only history and disk reopening.

## Storage and workflow

`MappingDraft.bartonQ` and `.rmr89` belong to the active mapping point and optional geological interval. `MappingObservation.ratings` contains optional immutable revision-1 assessment snapshots, timestamp, exact method/implementation identity, original inputs, input provenance and Q evaluation/missing list. Q results are validated against their stored input and method on every load/save; unknown versions and inconsistent result snapshots fail closed. RMR has no result or numerical rating field. Journal details show the saved snapshot rather than recalculate using future tables; validation recomputes this version only to detect inconsistency. No result is attached to an individual orientation reading or a J1–J5 representative.

Schema **5**, same `mapping-v1.json` path and bundle ID. Existing validated schema 1–4 journals pass through the established migration mechanism: non-overwriting exact-byte `pN-backup`, round-trip verification, source-change check, atomic replacement. Schema-4 records acquire no invented ratings. Backup conflicts, corrupt/unknown methods, invalid relationships and failed I/O block writes without resetting existing storage. Previous snapshots and append-only original point/measurement/plan validation are retained. Old app versions cannot read schema 5; downgrade requires explicit recovery planning.

Only the main `Сохранить наблюдение` commits point, original measurements, geology and ratings in the same graph write. Success resets all point fields including ratings, while retaining project/horizon/excavation and nominal horizon Z. Validation/I/O failure preserves the complete draft. A ratings-only change triggers the existing context discard/cancel guard. Drafts survive navigation/backgrounding in memory, not process termination. Saved source records are read-only; controlled correction revisions, multiple assessments of the same method and classification exports remain future work. The legacy standalone CSV is unchanged and is not a complete mapping backup.
