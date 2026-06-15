# Assessment Evaluation Flow

A step-by-step walkthrough of how a company runs an assessment in Way to Excellence — from creating the tool, through assigning contributors and auditors, to scoring and approval.

> **How to use this document:** Each `[SCREENSHOT: …]` block is a placeholder. Replace it in Google Docs with the matching screenshot from the app.

---

## 1. Overview

An assessment in Way to Excellence is organised around four layers:

1. **Standard** — the framework being assessed (e.g. EFQM, ISO 9001). Standards are ingested by the platform and contain a hierarchy of **Clauses**, each with **Checklist Items** (the requirements / questions).
2. **Tool** — a reusable scoring template. A tool defines **Checkpoints** and **Subcheckpoints** (the "scoring attributes") with weights, caps, and scoring types (Number / Percentage / Multiple Choice).
3. **Tool ↔ Standard Link** — a tool is linked to one or more terminal clauses of a standard, with points allocated per clause.
4. **Assessment** — one per (linked clause × company). This is where evidence is gathered, scores are entered, and approval happens.

[SCREENSHOT: High-level diagram or dashboard showing standards → tools → assessments]

---

## 2. Roles at a Glance

| Action | Company Admin | Quality Manager | Auditor | Contributor | Viewer |
|---|:---:|:---:|:---:|:---:|:---:|
| Create / configure a tool | — | — | — | — | — |
| Link a tool to a standard | — | — | — | — | — |
| Assign contributors to checkpoints | ✓ | ✓ | — | — | — |
| Assign the auditor | ✓ | ✓ | — | — | — |
| Upload evidence & write checkpoint summaries | ✓ | ✓ | ✓ | ✓ (only assigned items) | — |
| Enter scores on subcheckpoints | ✓ | ✓ | ✓ | — | — |
| Submit for review | ✓ | ✓ | ✓ | ✓ | — |
| Approve / request changes | ✓ | ✓ | — | — | — |
| View assessment | ✓ | ✓ | ✓ | ✓ | ✓ |

*Tool creation and standard linking are platform-level operations performed by a super admin or delegated admin, not by company users.*

---

## 3. Creating a Tool

Tools are created from the **Tools** admin area. A tool is a scoring template; you build its structure once and reuse it across any standard.

**Steps**

1. Go to **Tools → New Tool**.
2. Enter the tool **name** and **description**.
3. Add **Checkpoints** (the evaluation dimensions, e.g. *"Approach"*, *"Deployment"*, *"Assessment & Refinement"*).
4. Under each checkpoint, add **Subcheckpoints** (scoring attributes). For each subcheckpoint, configure:
   - **Scoring type** — `Number`, `Percentage`, or `Multiple Choice`.
   - **Weight** — a value between 0 and 1. If every subcheckpoint is left blank, equal weighting is applied automatically.
   - **Is Cap?** — when enabled, this subcheckpoint's score acts as a ceiling on the checkpoint total.
   - For `Number` types: **Min / Max score**.
   - For `Multiple Choice`: the list of options, each with a percentage value.
5. Save the tool.

[SCREENSHOT: "New Tool" form with checkpoints and subcheckpoints]

[SCREENSHOT: Subcheckpoint configuration showing scoring type, weight, and is_cap toggle]

---

## 4. Linking a Tool to a Standard

Once the tool exists, it must be linked to the clauses of a standard. This is what turns a generic scoring template into a concrete assessable clause for companies.

**Steps**

1. From the tool page, click **Link Standard**.
2. Choose the **Standard** and **Version**.
3. Select the terminal clauses you want the tool to score.
4. For each clause, allocate **Points** (the maximum contribution of that clause to the total standard score).
5. Save.

At this point an `Assessment` record becomes accessible for every company that has the standard assigned to them.

[SCREENSHOT: Link Standard screen with clause tree and points input]

---

## 5. Navigating into an Assessment

Company users reach an assessment from the standards library.

**URL pattern:** `/clauses/:clause_id/assessment`

**Steps**

1. Sign in as a Company Admin or Quality Manager.
2. Go to **Library → Standards** and open the active standard.
3. Drill down the clause tree to a **terminal clause** (leaf node).
4. Click **Assess** to open the clause assessment page.

The assessment page has three main regions:

- **Header** — clause code & title, status badge, navigation between sibling clauses, and the **Assign Auditor** button.
- **Checklist Items** — one block per requirement, each with its contributor list, scoring grid, and checkpoint summary fields.
- **Scoring & Approval** — visible to auditors and quality managers; shows the calculated clause score and the submit / approve controls.

[SCREENSHOT: Full assessment page at /clauses/:id/assessment]

---

## 6. Assigning an Auditor (per Assessment)

One auditor is responsible for reviewing and scoring an entire clause assessment.

**Who can do this:** Company Admin, Quality Manager.

**Steps**

1. On the assessment page header, click **Assign Auditor**.
2. Select a user from the modal's dropdown (only users with the *Auditor* role in the company are listed).
3. Click **Assign**.

The assigned auditor gains edit access to the scoring grid and the **Submit for Review** action for this clause.

[SCREENSHOT: Assign Auditor button in the header]

[SCREENSHOT: Assign Auditor modal with user dropdown]

---

## 7. Assigning Contributors (per Checkpoint)

Contributors are assigned at the **checklist-item** level — so different requirements within the same clause can be owned by different people.

**Who can do this:** Company Admin, Quality Manager.

**Steps**

1. Scroll to the checklist item you want to assign.
2. Click **+ Assign Contributor** below the contributors list.
3. In the modal, pick one or more users.
4. Click **Assign**. Selected contributors appear as chips under the checklist item.

Repeat per checklist item. A user can be removed by clicking the **×** on their chip.

[SCREENSHOT: Assign Contributor button below a checklist item]

[SCREENSHOT: Multi-user assignment modal with selected contributors]

---

## 8. Contributor Workflow

Once assigned, a contributor can work on their checklist item.

**What a contributor does**

- **Upload evidence** (documents, images) via the evidence panel on the checklist item.
- **Link existing documents** already uploaded to the company library.
- **Write a checkpoint summary** — a short (≤ 100 chars) narrative per (checkpoint × checklist item) that describes how the requirement is being met. Summaries auto-save as you type.
- **Submit for review** once the evidence and summaries are complete.

The assessment status moves from **Not Started** to **In Drafts** on the first save.

[SCREENSHOT: Evidence upload modal]

[SCREENSHOT: Checkpoint summary field with autosave indicator]

---

## 9. Scoring Workflow (Auditor / Quality Manager)

Scoring is entered in the **subcheckpoint grid** on each checklist item.

**Who can score:** Auditor (assigned to this assessment), Quality Manager, Company Admin.

**Steps**

1. Open the assessment page.
2. For each checklist item, enter a score in every subcheckpoint column, according to the subcheckpoint's scoring type:
   - **Number** — an integer between the configured min and max.
   - **Percentage** — 0–100.
   - **Multiple Choice** — pick the option that best describes the state.
3. Scores save as you move between fields.

The auditor can also leave a **comment / feedback** that will be surfaced to the quality manager on review.

[SCREENSHOT: Scoring grid with subcheckpoint inputs filled in]

[SCREENSHOT: Auditor comment / feedback panel]

---

## 10. How the Score Is Calculated

Clause scores are calculated by `ClauseScoreCalculator` and cached per assessment.

**Formula (per clause):**

```
weighted_sum     = Σ (subcheckpoint_score × subcheckpoint_weight)
cap_value        = min(score of subcheckpoints where is_cap = true)
overall_percent  = min(weighted_sum, cap_value)   # if any caps exist
                   else weighted_sum
clause_score     = allocated_points × overall_percent / 100
```

**Key rules**

- All subcheckpoint scores are normalised to a 0–100 percentage before being combined.
- If no weights are set on any subcheckpoint, equal weighting (1 / N) is applied automatically.
- Capped subcheckpoints do not add to the weighted sum — they impose a ceiling. The lowest capped score wins.
- The clause score rolls up to the parent clause by summing children, and ultimately to the overall standard score for that company.

[SCREENSHOT: Calculated clause score shown in the scoring section]

[SCREENSHOT: Rolled-up score on the standard dashboard]

---

## 11. Status Flow

An assessment moves through a small state machine:

| Status | Set by | Editable by |
|---|---|---|
| **Not Started** | (initial) | Anyone with write access |
| **In Drafts** | System, on first save | Contributors, Auditor, QM |
| **Under Review** | Contributor or Auditor submits | QM / Admin only |
| **Approved** | QM / Admin | Read-only |
| **Needs Changes** | QM / Admin rejects | Back to Contributors |

Typical transitions:

```
Not Started → In Drafts → Under Review → Approved
                                      ↘ Needs Changes → In Drafts (loop)
```

[SCREENSHOT: Status badge in the assessment header]

[SCREENSHOT: Submit-for-review button]

---

## 12. Approval / Request Changes

When an assessment is **Under Review**, a Quality Manager or Company Admin decides the outcome.

**Steps**

1. Review all checklist items, evidence, and the auditor's comment.
2. Verify the calculated clause score.
3. Click **Approve** to finalise, or **Request Changes** to send it back to contributors with feedback.

Approval is logged in the audit trail with the reviewer's identity and timestamp.

[SCREENSHOT: Approval controls — Approve / Request Changes buttons]

[SCREENSHOT: Feedback modal shown when requesting changes]

---

## 13. Audit Trail

Every key action — assignments, status transitions, approvals, score changes — is written to the audit log and visible on the assessment page's activity stream. Use this to trace who did what and when.

[SCREENSHOT: Activity / audit log panel on the assessment page]

---

## 14. Quick Reference — Common Tasks

| I want to… | Role needed | Where |
|---|---|---|
| Create a new scoring template | Super admin | Tools → New Tool |
| Link a tool to a standard clause | Super admin | Tool page → Link Standard |
| Assign who scores a clause | Company Admin / QM | Assessment header → Assign Auditor |
| Assign who gathers evidence | Company Admin / QM | Checklist item → + Assign Contributor |
| Upload evidence | Contributor (assigned) | Checklist item → Evidence panel |
| Enter scores | Auditor / QM / Admin | Scoring grid on each checklist item |
| Submit for review | Contributor / Auditor | Footer of assessment page |
| Approve or reject | QM / Admin | Scoring & Approval section |

---

*End of document.*
