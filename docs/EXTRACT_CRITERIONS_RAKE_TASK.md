# Extract Criterions Rake Task Documentation

## Overview

The `pdf:extract_criterions` rake task extracts hierarchical criterion structures from quality management standard PDF documents. It performs a two-stage extraction process: first identifying top-level criterions, then extracting sub-criterions and checkpoints for each criterion.

## Purpose

This task is designed to process quality management standard documents (EFQM, ISO 9001, ISO 27001, KAQA) and extract their complete hierarchical structure:
- Top-level criterions (numbered 1, 2, 3, etc.)
- Sub-criterions under each criterion (numbered 1.1, 1.2, etc.)
- Checkpoints under each sub-criterion

## Usage

```bash
rake pdf:extract_criterions[path/to/file.pdf]
rake pdf:extract_criterions['/absolute/path/to/file.pdf']
```

### Environment Variables

- `OLLAMA_URL`: Optional. Defaults to `http://localhost:11434`. Specifies the Ollama API endpoint.
- `DEBUG_CHUNKS`: Optional. Set to `true` to save debug chunk files for inspection.

## Process Flow

### Stage 1: Top-Level Criterion Extraction

1. **OCR Text Extraction**
   - Converts PDF pages to images using `pdftoppm`
   - Extracts text from each page image using Tesseract OCR
   - Supports English and Arabic languages
   - Saves extracted text for each page to `tmp/ollama_responses/extracted_text/`

2. **Text Chunking**
   - Divides the document into chunks of 4 pages each
   - Uses 1-page overlap between chunks to prevent missing criterions at boundaries
   - Example: Pages 1-4, 4-7, 7-10, etc.

3. **Criterion Extraction**
   - Sends each chunk to the `qwen-criterion-extractor` model
   - The model identifies top-level criterions (single-digit numbers: 1, 2, 3, etc.)
   - Extracts criterion numbers and titles
   - Can extract from both regular content and table of contents sections

4. **Consolidation**
   - Merges duplicate criterions found across multiple chunks
   - Filters out invalid entries (too short, contains fragments, etc.)
   - Keeps the longest title when duplicates are found

### Stage 2: Sub-Criterion Extraction

For each top-level criterion identified in Stage 1:

1. **Re-chunking for Sub-Criterions**
   - Re-chunks the entire document into 5-page chunks (with 1-page overlap)
   - This larger chunk size helps capture complete sub-criterion structures

2. **Sub-Criterion Extraction**
   - Sends each chunk to the `qwen-subcriterion-extractor` model
   - Provides the criterion number and title as context
   - The model extracts:
     - Sub-criterion numbers (e.g., 1.1, 1.2, 2.3)
     - Sub-criterion titles
     - Checkpoints under each sub-criterion
   - Saves each LLM response to `tmp/ollama_responses/subcriterions/`

3. **Consolidation**
   - Merges sub-criterions found across multiple chunks
   - Combines checkpoints from duplicate sub-criterions
   - Sorts sub-criterions by their numbering

## Output Files

### Final Output

The complete extraction results are saved to:
```
tmp/ollama_responses/criterions_complete_{filename}_{timestamp}.json
```

The JSON structure includes:
- Metadata (extraction timestamp, source file)
- Summary statistics (total criterions, subcriterions, checkpoints)
- Complete hierarchical structure with all criterions, sub-criterions, and checkpoints

### Intermediate Files

- **Extracted page text**: `tmp/ollama_responses/extracted_text/extracted_text_page_{number}_{timestamp}.txt`
- **Sub-criterion responses**: `tmp/ollama_responses/subcriterions/subcriterion_c{number}_chunk{index}_{timestamp}.txt`
- **Debug chunks** (if `DEBUG_CHUNKS=true`): `tmp/ollama_responses/debug_chunk_{index}.txt`

## Models Used

1. **qwen-criterion-extractor**
   - Purpose: Extract top-level criterions from document chunks
   - Input: Raw text chunk (4 pages)
   - Output: JSON array of criterion numbers and titles
   - Context window: 15000 tokens

2. **qwen-subcriterion-extractor**
   - Purpose: Extract sub-criterions and checkpoints for a specific criterion
   - Input: Criterion number, criterion title, and text chunk (5 pages)
   - Output: JSON structure with sub-criterions and their checkpoints
   - Context window: 15000 tokens

## Error Handling

The task includes error handling at multiple levels:
- OCR extraction failures fall back gracefully
- Invalid JSON responses are logged and skipped
- Individual chunk processing errors don't stop the entire process
- All errors are logged with descriptive messages

## Performance Considerations

- Processing time depends on document size and number of criterions
- Each LLM call includes a 0.5-second delay between chunks to avoid rate limiting
- Large documents may take significant time to process
- All intermediate results are saved for debugging and recovery

## Limitations

- Requires OCR tools (`pdftoppm` and `tesseract`) to be installed
- OCR quality affects extraction accuracy
- Model responses must be valid JSON
- Duplicate detection relies on criterion numbers matching exactly

## Troubleshooting

If extraction fails or produces incomplete results:

1. Check OCR quality by examining `tmp/ollama_responses/extracted_text/` files
2. Enable debug mode with `DEBUG_CHUNKS=true` to inspect chunk contents
3. Review subcriterion response files to see what the model extracted
4. Verify Ollama models are available and responding correctly
5. Check that the document structure matches expected quality standard formats



