# EFQM Scoring & Assessment

Welcome to the new EFQM Scoring feature in WTE Excellence. This guide walks you through everything you need to know to evaluate clauses, configure scoring tools, and understand how scores are calculated.

---

## What's New

WTE Excellence now supports **clause-level assessment** with a dedicated assessment page for each terminal clause (the lowest-level clauses in your standard hierarchy, such as "1.1 Define Purpose and Vision"). Instead of evaluating individual subcheckpoints separately, you now work on a single, consolidated page that brings together:

- **Checkpoint descriptions** with guided text fields
- **Evidence uploads** for supporting documentation
- **Scoring sliders** for each scoring attribute (e.g., Sound, Aligned, Implemented)
- **Automatic overall score calculation** using configurable weights and caps
- **One-click submission** for auditor review

This approach aligns with the EFQM assessment methodology and supports other standards like KAQA and ISO.

---

## For Assessors: Evaluating a Clause

### Opening the Assessment Page

1. Navigate to your standard (e.g., **EFQM 2020**) from the sidebar or standards list.
2. In the clause hierarchy, find a terminal clause (one that has no sub-clauses beneath it).
3. Click the action button on the clause row. You will be taken to the **Assessment Page**.

At the top of the page, you will see:

- **Breadcrumb navigation** showing the path: Standard > Parent Clause > Current Clause
- **Clause title and code** (e.g., "1.1 Define Purpose and Vision")
- **Status badge** showing the current state: Not Started, In Progress, Under Review, or Approved
- **Allocated points** and **current score percentage**
- **Previous / Next buttons** to move between sibling clauses without returning to the hierarchy

### Filling In Checkpoints

Below the header, you will see a **Checkpoint** section with numbered boxes. Each checkpoint represents a specific area to evaluate within the clause. For each checkpoint:

1. **Read the guidance text** displayed in the blue box at the top. This explains what the checkpoint is about.

2. **Fill in the text fields.** Depending on how your tool is configured, you may see one or more labeled text areas. For a typical EFQM tool, you will see three:
   - **Approach** -- Describe how your organization plans its approach
   - **Deployment** -- Describe how the approach is implemented
   - **Assessment & Refinement** -- Describe how you measure and improve

   Each text field allows up to **100 characters**. A live counter below each field shows how many characters you have used (e.g., "87/100").

3. **Attach evidence** by clicking "Upload File" to upload a document, or use the evidence linking system to associate existing files from your library.

4. **Assign contributors** -- On the right side of each checkpoint, you can assign contributors who will work on that specific checkpoint. Contributors only see the checkpoints they are assigned to.

**Auto-save:** Text boxes auto-save as you type (after 1 second of inactivity). Your work is preserved even if you navigate away without clicking Save Draft.

### Scoring Your Clause

Below the checkpoints, you will find the **Scoring** section. This is where you rate the clause across each scoring attribute.

**How the scoring section is organized:**

Scoring attributes are grouped by category (e.g., Approach, Deployment, Assessment & Refinement). Under each category, you will see individual attributes with sliders:

| Category | Attributes |
|----------|-----------|
| Approach | Sound, Aligned |
| Deployment | Implemented, Flexible |
| Assessment & Refinement | Evaluated & Understood, Learn & Improve |

**For each attribute:**

- **Drag the slider** left or right to set your score (0% to 100%, in steps of 10). The current value appears in a box to the right of the slider.
- **Hover over the question mark icon** (?) next to the attribute name to see a description of what it means.
- Attributes marked with a **CAP** badge have special behavior -- see "Understanding Caps" below.

**The Overall Score** at the bottom updates automatically as you adjust the sliders. You do not need to reload the page. Below the score bar, a formula breakdown shows exactly how the score was calculated.

### Saving Your Work

At the bottom of the page, you have two options:

- **Save Draft** -- Saves all your text, scores, and evidence without changing the status. Use this when you are still working and not ready for review. The clause status changes to "In Drafts." The button turns purple when there are unsaved changes.

- **Submit for Review** -- Saves everything and marks the clause as "Under Review." Your auditor will be notified and can review your work. Once submitted, the fields become read-only until the auditor responds.

### Assigning an Auditor

The auditor is assigned at the **assessment level** (not per checkpoint). In the clause header area, click "Assign Auditor" to select an auditor who will review all checkpoints for this assessment. The auditor can then approve, reject, or leave comments on the entire assessment.

### Comments

Below the checkpoints, the **Comments & Feedback** section shows all comments and review feedback. Auditors, Quality Managers, and Admins can post comments directly without submitting the full form -- comments appear inline immediately.

### After Submission

Once your auditor reviews the assessment:

- **If approved**, the auditor must provide a reason. The clause status changes to "Approved" and scores are finalized. Scores propagate upward to parent clauses and the overall standard compliance percentage.
- **If changes are requested**, the auditor must provide a reason for rejection. The clause status changes to "Needs Changes." You can edit your responses and re-submit.

All approval/rejection reasons are recorded in the Comments section and the Activity Log.

---

## Understanding the Score Calculation

### Weighted Scoring

Each scoring attribute (e.g., Sound, Aligned) has a **weight** assigned by your administrator. The weight determines how much that attribute contributes to the overall clause score. Weights are expressed as decimals that add up to 1.0 (100%).

**Example:**

| Attribute | Your Score | Weight | Contribution |
|-----------|-----------|--------|-------------|
| Sound | 65% | 0.20 | 13.0 |
| Aligned | 70% | 0.20 | 14.0 |
| Implemented | 55% | 0.20 | 11.0 |
| Flexible | 60% | 0.20 | 12.0 |
| Evaluated & Understood | 50% | 0.10 | 5.0 |
| Learn & Improve | 45% | 0.10 | 4.5 |
| | | **Weighted Sum** | **59.5%** |

The weighted sum is calculated as: (65 x 0.20) + (70 x 0.20) + (55 x 0.20) + (60 x 0.20) + (50 x 0.10) + (45 x 0.10) = **59.5%**

### Score Caps

Some attributes can be designated as **caps**. A cap means the overall clause score can never exceed that attribute's value, regardless of how high the other scores are. This is a key concept in EFQM scoring -- for example, if your approach is not "Sound" (well-defined and well-reasoned), a high overall score would be misleading.

**How caps work:**

- If **Sound** is a cap and its score is 65%, the overall score cannot exceed 65% -- even if the weighted sum is higher.
- If multiple attributes are caps, the overall score cannot exceed the **lowest** cap value.
- The formula display shows when a cap is applied: "Cap (Sound) = 65 | Overall = MIN(59.5, 65) = 59.5%"

**Example with a cap being applied:**

| Attribute | Score | Weight | Cap? |
|-----------|-------|--------|------|
| Sound | 20% | 0.20 | Yes |
| Aligned | 100% | 0.20 | No |
| Implemented | 100% | 0.20 | No |
| Flexible | 100% | 0.20 | No |
| Evaluated | 100% | 0.10 | No |
| Learn | 100% | 0.10 | No |

Weighted sum = (20 x 0.20) + (100 x 0.20) + (100 x 0.20) + (100 x 0.20) + (100 x 0.10) + (100 x 0.10) = **84%**

But because Sound is a cap at 20%, the overall score is **20%**, not 84%.

### Equal Weighting Fallback

If your administrator has not configured weights for any scoring attribute, all attributes are weighted equally. For example, with 6 attributes, each receives a weight of approximately 0.167 (1/6).

### Final Score Points

Your clause has a number of **Allocated Points** (shown in the header). The final point score is:

> Final Score = Allocated Points x (Overall Percentage / 100)

For example, if a clause has 100 allocated points and the overall score is 59.5%, the final score is **59.5 points**.

---

## For Administrators: Configuring a Scoring Tool

Administrators can create and configure evaluation tools that control how the assessment page looks and how scores are calculated.

### Creating or Editing a Tool

1. Navigate to **Tools** from the sidebar.
2. Click **Create New Tool** (or click an existing tool to edit).
3. Fill in the general information:
   - **Tool Name** (e.g., "EFQM Excellence Model")
   - **Description** of the tool's purpose

### Setting Up Assessment Categories

Assessment Categories determine the **text fields** that appear in each checkpoint box on the assessment page.

1. In the tool form, find the **checkpoints** section.
2. Add a new checkpoint for each category. For a typical EFQM tool:
   - "Approach"
   - "Deployment"
   - "Assessment & Refinement"
3. Each category you add creates a labeled text area in every checkpoint box on the assessment page.

**Tip:** If you are configuring an ISO tool, you might only need one category called "Fulfillment." Each checkpoint would then show a single text area.

### Setting Up Scoring Attributes

Under each Assessment Category, you define the **Scoring Attributes** that appear as sliders (or other input types) in the scoring section.

1. Under each category, click **"+ Add Sub-Checkpoint"** to add a scoring attribute.
2. For each attribute, configure:

| Field | Description | Example |
|-------|-------------|---------|
| **Name** | The attribute label shown on the assessment page | "Sound" |
| **Description** | Tooltip text explaining what this attribute means | "Clearly defined, well-reasoned" |
| **Scoring Type** | How the assessor provides the score | Percentage (slider), Number (input), or Multiple Choice |
| **Weight** | How much this attribute contributes to the overall score (0.0 to 1.0) | 0.20 |
| **Cap** | If enabled, the overall score cannot exceed this attribute's value | On / Off |

### Weight Configuration Tips

- Weights should add up to **1.0** (100%). A live warning banner appears above the checkpoints section if they do not sum correctly (e.g., "Weights sum to 0.85 (should be 1.0)"). Saving is still allowed.
- If you leave all weights empty, the system uses equal weighting automatically. An info banner indicates this: "No weights configured. Equal weighting will be applied automatically."
- You can use the **Weight** column in the form to enter values. Use increments like 0.05, 0.10, 0.20, etc.

### Cap Configuration Tips

- Enable the cap toggle for attributes that should limit the maximum overall score.
- In EFQM methodology, "Sound" is commonly configured as a cap, meaning the overall score cannot exceed the Sound rating.
- You can set multiple caps. When more than one cap is active, the overall score is limited by the **lowest** cap value.

### Saving Your Tool

Click **Save Tool** to save your configuration. The changes take effect immediately for all assessment pages that use this tool.

---

## Supported Standards

The scoring system is designed to work with multiple standards:

| Standard | Typical Setup |
|----------|--------------|
| **EFQM 2020** | 3 categories (Approach, Deployment, Assessment & Refinement) with 6 scoring attributes using percentage sliders. Sound is a cap. |
| **KAQA** | Similar to EFQM, with percentage-based sliders and configurable weights. |
| **ISO 9001** | 1 category ("Fulfillment") with simple Yes/No or point-based scoring. |

The tool configuration is flexible -- you can define any number of categories and any number of scoring attributes to match your organization's needs.

---

## User Roles and Permissions

| Role | Can View Assessment | Can Edit Text & Evidence | Can Score | Can Submit for Review | Can Approve/Reject | Can Comment | Can Assign |
|------|:------------------:|:----------------------:|:---------:|:--------------------:|:-----------------:|:-----------:|:----------:|
| Company Admin | Yes (all) | Yes | Yes | Yes | Yes | Yes | Yes |
| Quality Manager | Yes (all) | Yes | Yes | Yes | Yes | Yes | Yes |
| Contributor | Assigned checkpoints only | Yes (own checkpoints) | No | No | No | No | No |
| Auditor | Yes (all) | No | Yes | No | No | Yes | No |
| Viewer | Yes (read-only) | No | No | No | No | No | No |

**Contributors** are assigned per checkpoint and only see the checkpoints they are assigned to. They can write text and link evidence on their assigned checkpoints.

**Auditors** are assigned per assessment (not per checkpoint) and can see all checkpoints, score attributes, and leave comments. They review and approve/reject the entire assessment.

**Viewers** see the full assessment page but all fields are disabled and no action buttons are shown.

---

## Frequently Asked Questions

### General

**Q: Where do I find the assessment page for a clause?**
Navigate to your standard, find the terminal clause in the hierarchy, and click the action button. Terminal clauses are the lowest-level items that have no sub-clauses.

**Q: Can I work on an assessment across multiple sessions?**
Yes. Text boxes auto-save as you type. You can also click "Save Draft" to explicitly save all changes. When you return to the same clause later, all your text, evidence, and scores will be preserved.

**Q: What happens if I do not score all attributes?**
Unscored attributes are treated as 0% in the calculation. You can still save a draft and come back later, but be aware that the overall score will be lower until all attributes are scored.

**Q: Can I edit my assessment after submitting for review?**
Not while it is under review. Once the auditor responds:
- If approved, the assessment is finalized and cannot be changed.
- If the auditor requests changes, the fields become editable again and you can re-submit.

### Scoring

**Q: Why is my overall score lower than I expected?**
Check for **cap attributes**. If an attribute like "Sound" has a CAP badge and its score is low, the overall score is limited to that value. Look at the formula breakdown below the overall score bar to see if a cap was applied.

**Q: The formula shows my weighted sum is 80% but the overall is 50%. Why?**
A cap is being applied. One or more capped attributes have a lower score than the weighted sum. The overall score takes the minimum of the weighted sum and the lowest cap value.

**Q: What if I only see one text field per checkpoint instead of three?**
The number of text fields is determined by how the evaluation tool is configured. An ISO tool might have only one category ("Fulfillment"), while an EFQM tool has three (Approach, Deployment, Assessment & Refinement). Contact your administrator if the configuration does not match your expected standard.

**Q: Can I change the weights or caps?**
Weights and caps are configured by your administrator in the tool settings. If you believe the configuration needs adjustment, contact your Company Admin or Quality Manager.

### Administration

**Q: I changed the weights on my tool. Do existing assessments update automatically?**
Score caches are invalidated automatically when the tool configuration changes (including adding/removing checkpoints or subcheckpoints, changing weights, or deleting the tool). The next time anyone views an assessed clause, the scores will be recalculated with the new configuration. Score caches are also invalidated when clauses are deleted or moved in the standard tree.

**Q: What happens if weights do not add up to 1.0?**
The system calculates with whatever weights are configured. A warning is shown in the tool admin form, but saving is not blocked. For accurate results, ensure weights total exactly 1.0.

**Q: Can I use different tools for different clauses?**
Yes. When you link a standard to a tool, you can assign different tools to different clauses. Each clause uses the scoring configuration from its linked tool.

---

## Glossary

| Term | Definition |
|------|-----------|
| **Terminal clause** | The lowest-level clause in the hierarchy that has no child clauses. This is the level at which assessments are performed. |
| **Assessment category** | A group label (e.g., "Approach") that determines the text fields shown per checkpoint. Configured in the tool admin as checkpoints. |
| **Scoring attribute** | An individual criterion (e.g., "Sound") rated with a slider or input. Configured in the tool admin as subcheckpoints under each category. |
| **Weight** | A decimal (0.0 to 1.0) that controls how much a scoring attribute contributes to the overall score. |
| **Cap** | A constraint on the overall score. If a capped attribute has a score of X%, the overall score cannot exceed X%. |
| **Weighted sum** | The sum of each attribute's score multiplied by its weight. |
| **Overall score** | The final score for the clause: the minimum of the weighted sum and all active caps. |
| **Allocated points** | The maximum number of points assigned to a clause. The final point score is the overall percentage applied to these points. |
| **Checkpoint** | A specific item within a clause that the assessor must address. Each checkpoint has guidance text and input fields. |
