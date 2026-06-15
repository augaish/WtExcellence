PgSearch.multisearch_options = {
  using: {
    tsearch: {
      dictionary: "simple",
      prefix: true
    },
    trigram: {
      threshold: 0.2,  # Lower threshold for more lenient matching (was 0.3)
      word_similarity: true  # Use word_similarity for better multi-word query handling
    }
  }
}
