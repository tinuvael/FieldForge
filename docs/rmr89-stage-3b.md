# Stage 3b RMR89 engineering verification

The audit starts from main at `740c4bcc`, the merge of PR #77. It covers the Foundation evaluator and input types, the Russian capture and correction form, saved and historical assessments, the regulatory report, detailed XLSX/CSV, FieldForge Exchange export and read-only preview, and offline backup/restore.

## References and traceability

**Primary.** Z. T. Bieniawski, *Engineering Rock Mass Classifications*, Wiley-Interscience, 1989, ISBN 0-471-60172-1. Chapter 4, §4.1, pp. 52–59. Page numbers below are the printed book pages. The condition-detail table is **Chart E**, separately printed on p. 58. The later Hoek reproduction makes it section E of its own Table 4. [Wiley edition record][wiley], [digitized 1989 book][book].

**Secondary.** E. Hoek, *Practical Rock Engineering*, “Rock mass classification,” pp. 8–11, Tables 4–5. Used to cross-check the rows and for the independent tunnel example. The slope row in the original Table 4.1 B gives both end values explicitly. The linked Hoek reproduction leaves those ends blank. [Hoek chapter][hoek].

| FieldForge input and stable category IDs | Implemented row or score, in ID order | Reference and application |
| --- | --- | --- |
| Measured UCS, `strength-0…6` | >250, 100–250, 50–100, 25–50, 5–25, 1–5, <1 MPa → 15, 12, 7, 4, 2, 1, 0 | Bieniawski Table 4.1 A.1, pp. 54–55. Chart A on p. 56 is a separate graphical refinement. |
| Normalized point-load index Is(50), `is50-0…3` | >10, 4–10, 2–4, 1–2 MPa → 15, 12, 7, 4 | Table 4.1 A.1, pp. 54–55. The low range points to UCS testing and supplies no point-load bands below 1 MPa. FieldForge preserves the original Is(50) and leaves strength unscored below that limit. |
| Estimated intact strength, `R0…R6` | Approximate UCS grades 0.25–1, 1–5, 5–25, 25–50, 50–100, 100–250, >250 MPa → 0, 1, 2, 4, 7, 12, 15 | FieldForge crosswalk from the owner-adopted Appendix 6 Table 6 ISRM grades to Table 4.1 A.1. The 1989 table gives UCS/point-load scores. The grade observations and intervals come from the ISRM field method, also reproduced in Hoek (1994), Table 2. [Existing field-strength contract][enterprise], [ISRM-hosted grade reproduction][isrm]. |
| Core-quality RQD, `rqd-0…4` | 90–100, 75–90, 50–75, 25–50, <25% → 20, 17, 13, 8, 3 | Table 4.1 A.2, pp. 54–55, Chart B, p. 56. Zero RQD belongs to the lowest row. |
| Discontinuity spacing, `spacing-0…4` | >2, 0.6–2, 0.2–0.6, 0.06–0.2, <0.06 m → 20, 15, 10, 8, 5 | Table 4.1 A.3, pp. 54–55, Chart C, p. 57. §2.4, p. 22 describes perpendicular spacing. §4.1, p. 53 discusses the three-set basis. |
| Overall condition, `overallCondition-0…4` | 30 for very rough, discontinuous, closed and unweathered. 25 or 20 for slightly rough surfaces with <1 mm separation and slightly or highly weathered walls, respectively. 10 for continuous surfaces with slickensides, <5 mm gouge or 1–5 mm separation. 0 for continuous surfaces with >5 mm soft gouge or >5 mm separation. | Table 4.1 A.4, pp. 54–55. Direct rating replaces the Chart E sum. The Chart E footnote on p. 58 directs users to Table 4.1 when one condition masks another. |
| Persistence, `persistence-0…4` | <1, 1–3, 3–10, 10–20, >20 m → 6, 4, 2, 1, 0 | Chart E, p. 58. Length alone does not establish continuity for A.4. |
| Aperture, `aperture-0…4` | Closed, positive <0.1, 0.1–1, 1–5, >5 mm → 6, 5, 4, 1, 0 | Chart E, p. 58. Zero belongs to the closed row. |
| Roughness, `roughness-0…4` | Very rough, rough, slightly rough, smooth, slickensided → 6, 5, 3, 1, 0 | Chart E, p. 58. For gouge-covered joints use a supported direct A.4 description. |
| Infill, `infill-0…4` | None, hard <5, hard >5, soft <5, soft >5 mm → 6, 4, 2, 2, 0 | Chart E, p. 58. The numeric rows identify the categories. Known infill routes the condition score through A.4. Exactly 5 mm has no Chart E infill band in the printed table. |
| Wall weathering, `weathering-0…4` | Unweathered, slight, moderate, high, decomposed → 6, 5, 3, 1, 0 | Chart E, p. 58. Decomposition is the weathering category. |
| Groundwater, `groundwater-0…4` | Completely dry, damp, wet, dripping, flowing → 15, 10, 7, 4, 0. The corresponding inflows are 0, positive <10, 10–25, 25–125, >125 L/min per 10 m **of tunnel**. The corresponding joint-water-pressure/major-principal-stress ratios are 0, positive <0.1, 0.1–0.2, 0.2–0.5, >0.5. | Table 4.1 A.5, pp. 54–55. The three descriptions are alternative observations of each rating row. The raw ratio is dimensionless. |
| Orientation, `veryFavorable`, `favorable`, `fair`, `unfavorable`, `veryUnfavorable` | Tunnels and mines → 0, −2, −5, −10, −12. Foundations → 0, −2, −7, −15, −25. Slopes → 0, −5, −25, −50, −60. | Table 4.1 B, pp. 54–55. Table 4.2, p. 59, gives tunneling guidance by strike, dip and drive direction. §4.1, p. 53, refers to separate literature for slope and foundation interpretations. |
| Totals and classes | Basic = strength + RQD + spacing + condition + water. Adjusted = basic + signed application-specific correction. Classes I, II, III, IV and V use 81–100, 61–80, 41–60, 21–40 and 0–20, respectively. | §4.1, pp. 53 and 59, and Table 4.1 C, pp. 54–55. The book scan's OCR for the last cell reads “<20”. The app retains the 0–20 interpretation based on the stated 0–100 range, the adjoining 21 boundary and Hoek's explicit <21 in Table 4 C. |

## Confirmed defects and effect on new calculations

| Case | Before Stage 3b | Stage 3b |
| --- | --- | --- |
| A.4 is selected directly for a set with confirmed slight roughness, slight weathering and measured 0.5 mm separation. Other component scores are 12 + 13 + 10 + 7. | No condition or total, because Chart E selections were mandatory. | Condition 25, basic **67**. A.4 provides the whole condition score. |
| Explicitly confirmed continuous set with hard infill >5 mm and 8 mm separation. Same other four scores. | Incomplete even with A.4 selected. | Condition **0**, basic **42**. The measured separation supports the row independently of filling hardness. |
| Hard infill >5 mm and 0.5 mm separation with no A.4 match supported by the entered evidence. | Incomplete by a blanket hard-fill rule. | Incomplete until an applicable A.4 row can be documented. A contradictory chosen row is rejected. |
| Explicitly confirmed continuous set with soft gouge >5 mm, matching A.4 row and otherwise missing Chart E details. Same other four scores. | No basic total, because masked roughness and the other Chart E selections were required. | Condition **0**, basic **42**. The confirmed soft-gouge alternative is sufficient with continuity. |
| Dry row selected against 200 L/min per 10 m. Same Is(50), RQD, spacing and Chart E values as example 1. | Dry 15, basic **72**, despite the conflicting measurement. | The conflict blocks scoring. Selecting the compatible flowing row gives water **0**, basic **57**. |
| Example 1 with documented fair tunnel orientation. | Basic **64**, no adjusted result. | Basic **64**, correction **−5**, adjusted **59**. |
| Is(50) 0.9 MPa without a compatible selected row. | A generic missing-strength message. | A specific incomplete reason identifies the need for UCS to score this low-strength range. |

An A.4 row replaces the whole condition component. Previously entered Chart E categories and descriptions remain input evidence. See the A.4 follow-up below for the validation applied to new assessments.

The form keeps raw measurements, selected categories and results separate. A change of strength method clears the draft number and method-specific category, so an existing UCS number cannot be relabeled Is(50) or vice versa. Changing the engineering application clears the draft favorability choice. An unchanged correction draft displays its stored snapshot. Editing RMR inputs in a new observation revision invokes the current method.

## A.4 follow-up before merge

The original Table 4.1 A.4, pp. 54–55, places the continuity descriptor on the 30, 10 and 0 rows only. In the 10 and 0 rows it applies to every listed alternative. Section 2.4, pp. 22–23, discusses continuity at the scale of the excavation. The reviewer confirms it explicitly for the assessed set. A persistence length or a Chart E persistence category alone cannot supply that confirmation. [Digitized 1989 book][book].

| Points | Required together | Alternative evidence |
| --- | --- | --- |
| 30 | Discontinuous set, very rough surfaces, closed discontinuities, unweathered walls | None |
| 25 | Slightly rough surfaces, separation strictly below 1 mm, slightly weathered walls | None |
| 20 | Slightly rough surfaces, separation strictly below 1 mm, highly weathered walls | None |
| 10 | Continuous set and at least one listed alternative | Observed slickensides, gouge thinner than 5 mm regardless of hardness, or separation from 1 through 5 mm |
| 0 | Continuous set and at least one listed alternative | Soft gouge thicker than 5 mm or separation greater than 5 mm |

V3 could give a score when required descriptors were absent and accepted aperture ranges that merely overlapped a criterion. V4 requires positive evidence of all mandatory descriptors and at least one listed alternative where applicable. A missing or partially overlapping measurement leaves the condition and basic total incomplete. A definite contradiction in any mandatory descriptor, or in every alternative, rejects the row. Exact aperture is used when available. Without it, the entire selected Chart E aperture band must satisfy the A.4 criterion. For example, the 0.1–1 mm band alone cannot confirm strictly below 1 mm.

The Chart E footnote on p. 58 directs users to A.4 when gouge masks roughness. An obscured surface cannot supply a roughness observation. A.4 lists directly observed slickensides as its own 10-point alternative, without a separate no-gouge requirement. Hard gouge above 5 mm by itself supports neither the thin-gouge alternative at 10 nor the soft-gouge alternative at 0. A gouge thickness of exactly 5 mm satisfies neither thickness criterion. Independently confirmed aperture or another published alternative can still support the row. Where multiple rows apply, the table does not specify an automatic tie-break. [Digitized 1989 book][book].

For a basic subtotal of 42, a selected 10-point row and 2 mm separation previously produced **52** with no continuity evidence. In V4 the total stays incomplete until the engineer confirms continuity, after which it is **52**. A confirmed discontinuous set conflicts with the same row. A v3 snapshot with 52 basic and a −5 tunnel correction still opens with its original **47** adjusted and no added continuity evidence.

## Independent worked checks

Scores below come from the cited rows and arithmetic, independent of the evaluator.

1. **Tunnel, published by Hoek.** Is(50) 8 MPa in 4–10 → 12. RQD 70% in 50–75 → 13. Spacing 0.30 m in 0.2–0.6 → 10. Chart E condition uses persistence 1–3 m → 4, aperture in 0.1–1 mm → 4, slight roughness → 3, no infill → 6, slight weathering → 5, giving 22. Hoek's worked example specifies these categories. The test uses representative measurements 2 m and 0.5 mm inside the published categories. Wet → 7. Basic = 12 + 13 + 10 + 22 + 7 = **64 (II)**. A dominant set dipping 60° against a drive perpendicular to strike is fair under Table 4.2. Table 4.1 B gives −5, so adjusted = **59 (III)**. [Hoek worked example, pp. 8–11][hoek].
2. **Foundation and slope, synthetic orientation controls.** Use the same five original input categories and scores as example 1 to isolate the application effect. Independently supplied fair foundation orientation gives −7, so 64 − 7 = **57 (III)**. An independently supplied very unfavorable slope category gives −60, so 64 − 60 = **4 (V)**. A separately documented very favorable application gives a valid correction of 0 and adjusted **64 (II)**. These category assumptions exercise the Table 4.1 B lookup and do not derive foundation or slope favorability from the tunnel geometry.
3. **Field strength.** An intact specimen needs more than one hammer blow to fracture. Select R4, approximate 50–100 MPa → 7 by the field-grade crosswalk. Use RQD 70% → 13, spacing 0.30 m → 10, the five Chart E categories in example 1 → 22, and wet → 7. Basic = 7 + 13 + 10 + 22 + 7 = **59 (III)**. Without documented application and favorability the adjusted result is unavailable. An R0 field category in the same example gives a valid 0 for strength and basic **52 (III)**.
4. **Low UCS, zero components and out-of-scale adjustment.** UCS 0.5 MPa in <1 → 0, RQD 0% in <25 → 3, spacing 0.03 m in <0.06 → 5, explicitly confirmed continuous set with an 8 mm opening by A.4 → 0, and 200 L/min per 10 m in >125 → 0. Basic = 0 + 3 + 5 + 0 + 0 = **8 (V)**. A strike perpendicular to the tunnel and dip 30° against the drive is unfavorable under Table 4.2. Correction = −10. The signed result **−2** is displayed as outside the class scale. The audit found no Chapter 4 rule to clamp it to zero or assign a class.
5. **Groundwater and condition boundaries.** At 25 L/min per 10 m and a ratio of 0.2, both wet (7) and dripping (4) printed bands include the values. With the first four component scores 12 + 13 + 10 + 22 = 57, the explicit choice yields basic **64** or **61**, respectively. Orientation is unassessed. At 0 L/min and ratio 0, select dry (15) for basic **72**. A continuous 5 mm separation can satisfy the A.4 1–5 mm alternative (10), but cannot satisfy the >5 mm alternative. With the first example's other scores this gives basic **52**. Missing selection, even with numeric evidence, does not produce a score.

## Regulatory, storage and export review

- A1 and A45 are independent report inputs. Their optional fallbacks project an explicit R0–R6 grade or one of the first four equivalent RMR weathering categories **toward the report**. A45 crushed has its own ID and never resolves to RMR decomposed or vice versa. A42 and A43 reuse only the explicit Chart E persistence and aperture IDs because the owner-approved definitions, units and scores match. A direct A.4 choice and raw dimensions alone do not populate them. [Approved regulatory category definitions][reg].
- The RMR89 evaluator reads neither Barton Jr/Ja nor JCond76 for its condition score. The independent JCond76 descriptor retains its source and ID. RQD sources remain independent. The regulatory report exposes a Q/RMR RQD disagreement without changing either assessment. The UCS cell requires measured UCS and does not receive Is(50) or a field estimate.
- V4 adds an optional continuity confirmation to the assessment input. Schema remains 8. The input-only path remains available for original descriptions and measurements without scoring choices. The old input-only, v1 basic, v2 field-grade and initial v3 method IDs retain their exact validation paths and stored outputs. An unrelated correction copies the existing assessment. Loading, rendering, exporting and restoring preserve stored results. Decode-time validation checks each snapshot against its own method.
- Detailed XLSX lists basic score, signed correction, adjusted total, application, category and status. CSV, technical XLSX and Exchange keep their existing columns and carry continuity in the existing `input_json` payload. Exchange preserves the source records and protects saved results. The existing preview validates a proposal against its declared stored method. The regulatory workbook still targets only `Data!A:AD`. The audited backup/restore path carries the original bytes and historical J5.
- An explicit category remains necessary even when a raw value is present. At shared printed endpoints the engineer selects the applicable band. Any supplied numeric water alternatives must agree with the selected row for the same assessed zone. A mismatch is treated as conflicting evidence. Qualitative water descriptions remain original free text.

## Remaining limits

The implemented method is the discrete Table 4.1 and Chart E path. Charts A–D interpolation, correlation estimates, automatic selection or averaging of structural regions and sets, and optional spacing or mining-specific adjustments are outside this stage. The engineer supplies representative data for the assessed zone and documents the selected orientation category. FieldForge does not derive favorability from angles or north references. Table 4.2 is tunnel guidance, and its treatment of oblique strike and shared dip endpoints does not supply a unique automatic rule. Foundation and slope favorability requires an independent engineering interpretation. Table 4.1 D support or material-property estimates, SMR, and RMR76 scoring are outside the implementation.

## Verification

- A.4 follow-up passed **25 targeted SwiftPM tests**, including missing and contradictory evidence for all five A.4 rows, explicit continuity independent of persistence, aperture endpoints, v3/v4 snapshot validation, Exchange and backup/restore. One generic iOS Simulator build passed with Xcode 26.6 (17F113). Full regression and interactive simulator tests were outside the follow-up.
- Targeted SwiftPM verification passed **24 tests**. Fifteen calculation, history and workbook tests passed. The existing opt-in workbook fixture was skipped. Nine additional focused tests passed for field strength, regulatory independence, JCond76, input-only evidence, Exchange and backup/restore. The restore test checked the exact mapping bytes, the saved adjusted rating and historical J5.
- One generic iOS Simulator build passed with Xcode 26.6 (17F113), scheme `FieldForge` and `CODE_SIGNING_ALLOWED=NO`.
- `git diff --check` passed. Full SwiftPM/Xcode regression, interactive simulator UI tests and physical device checks were outside this verification run.

[wiley]: https://www.wiley-vch.de/en/areas-interest/natural-sciences/engineering-rock-mass-classifications-978-0-471-60172-2
[book]: https://www.scribd.com/document/352756092/Bieniawski-Engineering-rock-mass-clasification-pdf
[hoek]: https://www.rocscience.com/assets/resources/learning/hoek/Practical-Rock-Engineering-Chapter-3-Rock-Mass-Classification.pdf
[isrm]: https://isrm.net/download/media.file.afcfaa77c2928214.313333323136393339396973726d5f6e6577736a6f75726e616c5f2d5f313939342c5f766f6c756d655f322c5f6e756d.pdf
[enterprise]: enterprise-geotechnical.md
[reg]: regulatory-excel-audit.md#owner-specified-enterprise-category-descriptions
