# Reflection on Review 03 (Bilingual platform test, revised) and the Homepage review

Date: 9 September 2026. Reviewer's observations predate the deploy of Phases 1–5; some items are already fixed on the branch and marked so.

Verdict key: **Fix now** (real defect, in scope) · **Fix later** (valid, not blocking) · **Design choice, keep** (we disagree or it is by design) · **Not ours to decide** (business / marketing decision).

## Platform report — Q01 to Q18

| # | Reviewer's point | Verdict | Why / what we do |
|---|---|---|---|
| Q01 | Authority document prints "All amounts" and omits the saved limit text | **Fix now** | Confirmed in code: the document still prints the internal band label. It must print the authority's limit text, and say nothing when there is none. Published versions are snapshots and stay as printed. |
| Q02 | Legacy "Add Executive DoA" from Records opens the Policy form | **Fix now** | Confirmed. For DoA types, Add and Back must lead to Authorities & Delegations, never to a Records form. |
| Q03 | Procedure document prints an internal object as the owner | **Fix now** | Confirmed, a bug from Phase 3: the wrong helper formats the owning unit. One line, plus a regression test on every object-valued field in the document. |
| Q04 | Final AI root-cause step can fail with a raw parser message | **Fix now (message), keep the retry** | Retry already retains answers (the reviewer confirms). The remaining gap is the wording: the reader must never see parser internals. Show a plain message with Retry and Continue manually. |
| Q05 | Generated CAPA actions become "Started" at once, no review | **Fix now** | Confirmed and it contradicts the homepage. Generated actions become **Proposed** drafts with keep / discard / edit, owner and due date before they start. Charge once. |
| Q06 | Large org chart off-centre, Arabic labels at box edges, zoom-out no overview | **Half fixed, rest now** | Arabic labels and zoom are already on the branch (Phase 1 and 5). Still to do: centre on the root, Fit-to-view, search a unit, collapse a branch. |
| Q07 | SLA tab and help promise a journey that no longer exists | **Fix now (hide), decide later (SLA)** | You dropped SLA from Records. Hide the empty SLA tab in Packages and the help text. Whether SLA returns as its own capability is your call; the reviewer's section 7 is a fair spec if it does. |
| Q08 | Diagram asks again for trigger/inputs/outputs; early document lacks step narrative; no edit/reorder in the editor | **Partly by design, small fix** | Steps and the drawing already sync both ways (Phase 4). Remove the duplicated trigger/inputs/outputs from the diagram form when it belongs to a procedure; the document already prints the steps table. Reordering in the drawing stays as is. |
| Q09 | Arabic gaps: risk/vendor/commitment status options, Likelihood/Impact, validation headings, weekdays, library keys | **Fix now** | Confirmed: several forms build options with `titleize`. Translate enums, weekdays and the sampled labels; keep the terminology list. |
| Q10 | Drafts look final; "publication date" label for effective date; admin can move a record with no verifier/head | **Fix now (labels), keep (admin override)** | Add a visible DRAFT / stage line on unpublished documents and print the real published date separately. The admin path is deliberate: an admin may act in every stage; we will write that rule into Help rather than remove it. |
| Q11 | Evidence picker shows raw filenames; no open link; "Company visible" vs Public/Private wording | **Fix later** | Valid usability. Show title, folder and an Open link in the picker; align the visibility words. Not a blocker. |
| Q12 | Vendor rating has no assessment basis | **Design choice, keep for now** | The register is a simple one by design. Assessment versions, evidence and approval state are the roadmap in section 8; not a release fix. |
| Q13 | Risk closure reason only visible as a truncated activity line | **Fix later (small)** | Show a closure block (reason, who, when) on the risk page. |
| Q14 | One stale form after a commitment submission | **Watch** | Observed once, record was created. We will make the submit button re-enable on error and show the created record link; no root cause proven. |
| Q15 | Accessible names on row menus / selectors; mobile tables | **Fix later** | Row menus were named in the retest batch; the remaining ones (custom selectors, dates) get labels. Mobile cards for registers are a design task, later. |
| Q16 | Authorities page slow (3–4 s) with many units | **Fix now** | Confirmed cause: a searchable picker is rendered in every one of six boxes for every authority. Load the picker only when Assign is opened. |
| Q17 | "Working week" asks for non-working days; two "Published" rows; Structure Settings help; credit pools; Arabic terms | **Fix now (small)** | Rename to Non-working days; give the glossary's Published stage its own name in settings; drop the obsolete level-names help; label company pool vs my credits. |
| Q18 | Help and marketing claims do not match the current scope | **Fix now (Help), marketing separate** | Rewrite the P&P and DoA help topics for the current flows (no bands, five record types, the exact stage lists). Marketing claims are the homepage report. |

Sections 5, 7, 8 (journeys, SLA spec, governance roadmap): useful direction, none of it is a defect. Parked in BACKLOG as roadmap.

Section 6 (speed): Authorities is the only slow page; Q16 covers it. The rest is within reason for an admin app.

Delegation expiry (section 7): already built with a clock-driven test matrix in the retest batch; the reviewer asks to see the evidence, which is `test/jobs/delegation_gate_c_test.rb`.

## Homepage report — H01 to H12

| # | Point | Verdict | Why |
|---|---|---|---|
| H01 | Claims stronger than the product (AI actions "reviewable before saving") | **Fix the product, not the copy** | Q05 makes the claim true. The broader wording ("complete audit trail") is fair for what exists; keep a claim register as a habit. |
| H02 | Primary CTA: waitlist vs demo vs pilot | **Not ours to decide** | Depends on how you sell. If you take demos, "Request a demo" converts better than a waitlist; if access is limited, say "Request a pilot". Say what happens next either way. |
| H03 | Explain the buyer and outcome earlier | **Optional** | Copy direction, reasonable; only worth doing with your own words and a few buyers' reactions. |
| H04 | Story misses P&P, Documenter, architecture, authorities | **Agree, fix** | The new half of the product is absent from the page. Add a "Processes, documents and decisions" section with three paths. |
| H05 | Illustrative percentages not labelled as demo | **Agree, small** | Add "Illustrative" to the sample panels. Real screenshots when a stable demo tenant exists. |
| H06 | No Privacy / Terms / About / Security links; email domain differs from site domain | **Agree, needs your text** | The pages need content only you can approve; the links and a consistent contact address are quick once the text exists. |
| H07 | Waitlist form lacks back / language / privacy links; ask less | **Agree, small** | Add navigation and the privacy link; keep the fields you need for qualification. |
| H08 | Low contrast on secondary text; no main landmark | **Agree, trivial** | Darken two text colours; add `<main>` and a skip link. |
| H09 | Same URL for both languages; no hreflang / Open Graph | **Agree, medium** | Stable `/en` and `/ar` URLs with hreflang and share previews. Real SEO value for a bilingual buyer. |
| H10 | Mobile LCP 2.7 s; render-blocking assets; image sizes | **Agree, small** | Sizes on images, lazy-load below the fold, defer non-critical CSS. Scores are already 92/98. |
| H11 | Desktop hero too tall; Prove missing from nav | **Cosmetic** | Shorten the headline or reduce top spacing; add Prove to the nav. |
| H12 | Arabic marketing copy too literal | **Needs your Arabic reviewer** | The suggested replacements are reasonable; final wording is a brand decision. |

## Status (10 September)
Phases 6, 7, 8 and 9 (Q12) and the homepage items H04, H05, H07, H08, H09, H10, H11 are built. Hero kept as is (owner's decision). H02, H06 and H12 wait on the owner's text.

## Proposed plan

Phase 6 — correctness (do first): Q01, Q02, Q03, Q05, Q04 message, Q10 labels, Q17 wording, Q07 hide SLA tab, Q08 duplicate fields.
Phase 7 — Arabic and access: Q09 enums / weekdays / validation, Q15 remaining labels, Q18 help rewrite.
Phase 8 — chart and speed: Q06 fit / search / collapse, Q16 lazy pickers, Q13 closure block, Q11 picker titles.
Homepage — after your decisions on H02, H06 text and H12: H04, H05, H07, H08, H09, H10, H11.
Roadmap (BACKLOG): Q12, sections 5, 7, 8; mobile cards; SLA capability if revived.
