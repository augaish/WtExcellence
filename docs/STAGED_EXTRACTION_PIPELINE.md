# Multi-Stage Quality Standard Extraction Pipeline

## Overview

This rake task implements a comprehensive 5-stage pipeline for extracting and processing quality management standard documents (EFQM, ISO 9001, ISO 27001, KAQA) using LLMs.

## Prerequisites

- **Apache Tika**: Install via `brew install tika` (macOS) or `apt-get install tika` (Linux)
- **Ollama**: Running locally or accessible via URL
- **Model**: `qwen-wte` or custom model with appropriate system prompt

## Pipeline Stages

### Stage 0: Text Extraction & Cleanup (Algorithmic)
- Extracts text from PDF using Apache Tika
- Applies algorithmic cleanup:
  - Normalizes whitespace (max 2 consecutive spaces)
  - Removes non-characters (keeps bullets, Arabic, English, numbers, punctuation)
  - Splits into pages (~5000 chars each)
  - Creates chunks with overlap for context preservation

### Stage 1: Structure Detection
- Detects structural blocks (criteria, sub-criteria, checkpoints)
- Identifies clause IDs and hierarchy levels
- Determines parent-child relationships
- Filters out table of contents and non-content sections
- Preserves original numbering formats (dots for EFQM/ISO, dashes for KAQA)

### Stage 2: Content Extraction
- Extracts clause names (titles) and body text
- Cleans and normalizes content while preserving meaning
- Handles corrupted text gracefully
- Does NOT translate at this stage

### Stage 3: Translation
- Detects source language (Arabic or English)
- Produces full bilingual output
- Maintains technical accuracy and Arabic RTL order
- Preserves corrupted text markers

### Stage 4: Final Assembly
- Assembles all processed blocks into hierarchical model
- Ensures proper nesting (criteria → sub-criteria → checkpoints)
- Orders clauses sequentially
- Includes model metadata if present

## Usage

### Basic Usage

```bash
rake pdf:extract_standard_staged[/path/to/standard.pdf]
```

### With Custom Ollama Configuration

```bash
OLLAMA_URL=http://remote-server:11434 \
OLLAMA_MODEL=qwen-wte \
rake pdf:extract_standard_staged[/path/to/standard.pdf]
```

### Example

```bash
rake pdf:extract_standard_staged[tmp/efqm2025.pdf]
```

## Output

### Directory Structure

```
tmp/ollama_responses/
├── staged/
│   ├── stage1_structure/
│   │   ├── stage1_structure_1_20260109_120000.txt
│   │   ├── stage1_structure_2_20260109_120015.txt
│   │   └── ...
│   ├── stage2_extraction/
│   │   ├── stage2_extraction_1_20260109_120100.txt
│   │   └── ...
│   ├── stage3_translation/
│   │   ├── stage3_translation_1_20260109_120200.txt
│   │   └── ...
│   ├── stage4_assembly/
│   │   └── stage4_assembly_final_20260109_120300.txt
│   ├── progress/                    # NEW - Progress snapshots
│   │   ├── progress_stage1_blocks_efqm2025_20260109_120030.json
│   │   ├── progress_stage2_extracted_efqm2025_20260109_120130.json
│   │   ├── progress_stage3_translated_efqm2025_20260109_120230.json
│   │   └── ...
│   └── failed/
│       ├── FAILED_stage1_1_20260109_120030.txt
│       └── ...
└── standard_staged_efqm2025_20260109_120300.json  # Final output
```

### Final Output Schema

```json
{
  "extracted_at": "2026-01-09T12:03:00Z",
  "source_file": "/path/to/standard.pdf",
  "extraction_method": "multi_stage_pipeline",
  "model": {
    "name_ar": "النموذج الأوروبي للتميز",
    "name_en": "EFQM Excellence Model",
    "award": "EFQM Excellence Award",
    "total_points": 1000,
    "principles": [],
    "criteria": [
      {
        "id": 1,
        "name_ar": "الغرض والرؤية والاستراتيجية",
        "name_en": "Purpose, Vision & Strategy",
        "points": 100,
        "subcriteria": [
          {
            "id": "1.1",
            "name_ar": "تحديد الغرض والرؤية",
            "name_en": "Defines Purpose & Vision",
            "points": 50,
            "subcriteria": [],
            "checkpoints": [
              {
                "id": "1.1.1",
                "text_ar": "...",
                "text_en": "..."
              }
            ]
          }
        ]
      }
    ]
  }
}
```

## Key Features

### Progress Tracking
- Saves progress after each stage completes
- Each stage output saved to `progress/` directory
- Allows monitoring of extraction status
- Can inspect intermediate results at any stage
- Useful for debugging and optimization

### Robust Error Handling
- Saves all LLM responses for debugging
- Logs failed JSON parses with detailed error info
- Continues processing even if individual blocks fail
- Provides detailed progress output

### Deduplication
- Removes duplicate blocks based on ID
- Keeps block with longest/most complete text

### Smart Chunking
- 1 page per chunk for focused processing
- Overlapping context (500 chars) for continuity
- Respects 16K context limit

### Quality Preservation
- Preserves original numbering formats
- Maintains technical terminology
- Handles corrupted text gracefully
- Keeps Arabic RTL order correct

## Advantages Over Simple Extraction

1. **Better Accuracy**: Each stage focuses on one specific task
2. **Easier Debugging**: Can inspect/fix issues at each stage
3. **Progress Monitoring**: See results after each stage completion
4. **More Maintainable**: Can update individual stage prompts
5. **Resource Efficient**: Respects GPU memory limits with smaller chunks
6. **Handles Complexity**: Works with corrupted/incomplete PDFs
7. **Resumable**: Can analyze intermediate results and restart from any stage

## Troubleshooting

### Tika Not Found
```bash
brew install tika  # macOS
apt-get install tika  # Linux
```

### Context Window Exceeded
- Reduce `chars_per_page` in `split_text_into_pages` (default: 5000)
- Reduce overlap in `create_chunks_with_overlap` (default: 500)

### Poor Quality Results
- Check staged response files to identify problematic stage
- Review and adjust stage-specific prompts
- Verify model is correct (`qwen-wte` with proper system prompt)

### JSON Parse Errors
- Check `failed/` directory for raw responses
- Look for smart quotes, control characters, or malformed JSON
- May need to adjust `clean_json_response` function

## Comparison with extract_criterions

| Feature | extract_criterions | extract_standard_staged |
|---------|-------------------|------------------------|
| Stages | 2 (top-level, then sub) | 5 (structure, extract, translate, assemble) |
| Chunking | 3-4 pages | 1 page with overlap |
| Models | 2 specialized models | 1 model with different prompts |
| Translation | Combined with extraction | Separate stage |
| Output | Criterions + sub-criterions | Full hierarchical model |
| Best For | Simple documents | Complex/corrupted documents |

## Performance

For a typical 50-page standard document:
- **Stage 0**: ~5-10 seconds (Tika extraction)
- **Stage 1**: ~50-100 seconds (1-2s per page)
- **Stage 2**: ~2-5 minutes (depends on block count)
- **Stage 3**: ~2-5 minutes (depends on block count)
- **Stage 4**: ~10-30 seconds (assembly)
- **Total**: ~10-20 minutes

*Times vary based on hardware, model size, and document complexity.*

## Progress Files

After each stage completes, a progress file is saved with the following structure:

```json
{
  "stage": "stage1_blocks",
  "timestamp": "2026-01-09T12:00:30Z",
  "source_file": "/path/to/standard.pdf",
  "total_items": 156,
  "data": [
    {
      "id": "1",
      "level": "criterion",
      "parent_id": null,
      "raw_text": "...",
      "source_page": 5
    },
    ...
  ]
}
```

### Progress File Locations

- **Stage 1 (Structure Detection)**: `progress_stage1_blocks_*.json`
  - Contains all detected structural blocks with hierarchy
  - Includes source page numbers and raw text
  
- **Stage 2 (Content Extraction)**: `progress_stage2_extracted_*.json`
  - Contains blocks with extracted names and text
  - Shows cleaned content before translation
  
- **Stage 3 (Translation)**: `progress_stage3_translated_*.json`
  - Contains fully bilingual blocks
  - Ready for final assembly

### Using Progress Files

**Monitor extraction progress:**
```bash
# Watch the progress directory
watch -n 5 'ls -lh tmp/ollama_responses/staged/progress/'

# Check latest progress
cat tmp/ollama_responses/staged/progress/progress_stage3_translated_*.json | jq '.total_items'
```

**Inspect specific stage results:**
```bash
# See what Stage 1 detected
cat tmp/ollama_responses/staged/progress/progress_stage1_blocks_*.json | jq '.data[0:5]'

# Count blocks by level
cat tmp/ollama_responses/staged/progress/progress_stage1_blocks_*.json | \
  jq '.data | group_by(.level) | map({level: .[0].level, count: length})'

# Find blocks missing translations
cat tmp/ollama_responses/staged/progress/progress_stage3_translated_*.json | \
  jq '.data[] | select(.name_en == null or .name_ar == null)'
```

