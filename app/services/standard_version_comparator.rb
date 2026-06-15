# StandardVersionComparator
#
# Compares two versions of a standard to identify differences (added, removed, modified, unchanged items).
#
# ## Input Parameters:
#
# ### current_version (StandardVersion ActiveRecord object)
#   - The NEWER version being compared (usually the latest or the one being edited)
#   - Structure:
#     - Has many: clauses (hierarchical tree structure)
#     - Each clause has:
#       - code: String (e.g., "1", "1.1", "2.3.1")
#       - stable_key: String or nil (e.g., "clause_1", "subcriterion_1_2")
#       - parent: Clause or nil (for hierarchical structure)
#       - clause_translations: Array of translations
#         - language_code: "en" or "ar"
#         - title: String (e.g., "Scope", "النطاق")
#         - summary: String
#         - body: String
#       - children: Array of Clause objects (subclauses)
#       - checklist_items: Array of ChecklistItem objects (checkpoints)
#         - item_type: "requirement", "question", "control", or "note"
#         - sort_order: Integer (position within parent clause)
#         - checklist_item_translations: Array of translations
#           - language_code: "en" or "ar"
#           - text: String (the checkpoint text)
#           - guidance: String (optional guidance text)
#
# ### compare_version (StandardVersion ActiveRecord object)
#   - The OLDER version to compare against
#   - Same structure as current_version
#
# ## Example Structure:
#
#   current_version (v2.0):
#     ├── Clause "1" (code: "1", title: "Scope")
#     │   ├── Clause "1.1" (code: "1.1", title: "General Requirements")
#     │   │   ├── ChecklistItem (sort_order: 0, text: "Document scope")
#     │   │   └── ChecklistItem (sort_order: 1, text: "Identify processes")
#     │   └── Clause "1.2" (code: "1.2", title: "Application")
#     │       └── ChecklistItem (sort_order: 0, text: "Determine applicability")
#     ├── Clause "2" (code: "2", title: "References")
#     └── Clause "3" (code: "3", title: "Terms")
#         └── Clause "3.1" (code: "3.1", title: "Quality")
#
#   compare_version (v1.0):
#     ├── Clause "1" (code: "1", title: "Scope")  # Same code, might have different content
#     │   ├── Clause "1.1" (code: "1.1", title: "General")  # Modified title
#     │   │   └── ChecklistItem (sort_order: 0, text: "Document the scope")  # Modified text
#     │   └── Clause "1.2" (code: "1.2", title: "Application")  # Unchanged
#     ├── Clause "2" (code: "2", title: "References")  # Unchanged
#     └── Clause "3" (code: "3", title: "Terms")
#         └── Clause "3.1" (code: "3.1", title: "Quality")
#         └── Clause "3.2" (code: "3.2", title: "QMS")  # This was removed in v2.0
#
# ## Comparison Process:
#
#   1. Build tree structures from both versions (clauses → subclauses → checkpoints)
#   2. Match items by code (or stable_key if available):
#      - Clauses: matched by code (e.g., "1.1" matches "1.1")
#      - Checkpoints: matched by parent_code + sort_order (e.g., "1.1_checkpoint_0")
#   3. Compare content (titles, text, translations) to detect changes
#   4. Classify each item:
#      - "added": exists in current_version but not in compare_version
#      - "removed": exists in compare_version but not in current_version
#      - "modified": exists in both but content changed
#      - "unchanged": identical in both versions
#
# ## Output:
#
#   Returns a hash with:
#   {
#     summary: {
#       added_count: Integer,
#       removed_count: Integer,
#       modified_count: Integer,
#       unchanged_count: Integer
#     },
#     tree: [
#       {
#         id: String,
#         type: "clause" or "checkpoint",
#         code: String,
#         status: "added" | "removed" | "modified" | "unchanged",
#         old_content: Hash or nil,  # Content from compare_version
#         new_content: Hash or nil,  # Content from current_version
#         children: Array  # Nested items (subclauses or checkpoints)
#       },
#       ...
#     ]
#   }
#
class StandardVersionComparator
  attr_reader :current_version, :compare_version


  DIFF_TYPES = {
    added: "added",
    removed: "removed",
    modified: "modified",
    unchanged: "unchanged",
    moved: "moved"
  }.freeze

  def initialize(current_version, compare_version, locale: :en)
    # current_version: StandardVersion object (newer version)
    # compare_version: StandardVersion object (older version to compare against)
    @current_version = current_version.root_clauses
    @compare_version = compare_version.root_clauses
    @current_map = {}
    @old_map = {}
    @locale = locale.to_sym
    @text_fields = locale_text_fields
  end

  def locale_text_fields
    case @locale
    when :ar
      { text: :text_ar, title: :title_ar, body: :body_ar, summary: :summary_ar }
    else # :en
      { text: :text, title: :title, body: :body, summary: :summary }
    end
  end

  def generate_diff
    compute_diff
  end

  def compute_diff
    # Eager load associations to avoid N+1 queries
    current_clauses = @current_version.includes(:clause_translations, :checklist_items, children: [ :clause_translations, :checklist_items ])
    compare_clauses = @compare_version.includes(:clause_translations, :checklist_items, children: [ :clause_translations, :checklist_items ])

    build_maps(current_clauses.to_a, @current_map)
    build_maps(compare_clauses.to_a, @old_map)

    # Build unified tree from both versions
    unified_tree = build_unified_tree(current_clauses.to_a, compare_clauses.to_a)
    summary = calculate_summary(unified_tree)

    {
      summary: summary,
      tree: unified_tree
    }
  end

  def build_unified_tree(current_nodes, old_nodes)
    # Create maps by title for matching at this level (match by content, not code)
    current_by_title = {}
    old_by_title = {}

    # Index nodes by title at this level only (not recursively)
    current_nodes.each do |node|
      title = get_clause_title(node)
      if title.present?
        # Use title as key, but store array in case of duplicates
        current_by_title[title] ||= []
        current_by_title[title] << node
      end
    end

    old_nodes.each do |node|
      title = get_clause_title(node)
      if title.present?
        old_by_title[title] ||= []
        old_by_title[title] << node
      end
    end

    # Get all unique titles from both versions at this level
    all_titles = (current_by_title.keys + old_by_title.keys).uniq

    all_titles.flat_map do |title|
      current_matches = current_by_title[title] || []
      old_matches = old_by_title[title] || []

      # Match by position/index if multiple clauses have same title
      max_count = [ current_matches.length, old_matches.length ].max

      (0...max_count).map do |index|
        current_node = current_matches[index]
        old_node = old_matches[index]

        if current_node && old_node
          # Exists in both - check if modified (title is same, but check other content)
          status = clause_content_changed?(old_node, current_node) ? DIFF_TYPES[:modified] : DIFF_TYPES[:unchanged]
          build_unified_node(current_node, old_node, status)
        elsif current_node
          # Only in current (new) version - added
          build_unified_node(current_node, nil, DIFF_TYPES[:added])
        else
          # Only in old version - removed
          build_unified_node(nil, old_node, DIFF_TYPES[:removed])
        end
      end
    end.compact
  end

  def get_clause_title(node)
    translations = node.clause_translations.index_by(&:language_code)
    en_translation = translations["en"] || translations.values.first
    en_translation&.title || node.code
  end

  def clause_content_changed?(old_node, new_node)
    # Compare title, summary, and body (but not code or children)
    old_translations = old_node.clause_translations.index_by(&:language_code)
    new_translations = new_node.clause_translations.index_by(&:language_code)

    old_en = old_translations["en"] || old_translations.values.first
    new_en = new_translations["en"] || new_translations.values.first
    old_ar = old_translations["ar"]
    new_ar = new_translations["ar"]

    # Compare only content fields, not code
    (old_en&.title != new_en&.title) ||
    (old_ar&.title != new_ar&.title) ||
    (old_en&.summary != new_en&.summary) ||
    (old_ar&.summary != new_ar&.summary) ||
    (old_en&.body != new_en&.body) ||
    (old_ar&.body != new_ar&.body)
  end

  def build_unified_node(current_node, old_node, status)
    current_content = current_node ? build_node_content(current_node) : nil
    old_content = old_node ? build_node_content(old_node) : nil

    # Determine codes (show both if different)
    old_code = old_node&.code
    new_code = current_node&.code
    display_code = new_code || old_code

    # Build children
    current_children = current_node ? current_node.children.ordered.to_a : []
    old_children = old_node ? old_node.children.ordered.to_a : []
    children = build_unified_tree(current_children, old_children)

    # Build checkpoints
    current_checkpoints = current_node ? current_node.checklist_items.ordered.to_a : []
    old_checkpoints = old_node ? old_node.checklist_items.ordered.to_a : []
    checkpoints = build_unified_checkpoints(current_checkpoints, old_checkpoints)

    {
      id: display_code || old_code || new_code,
      type: "clause",
      code: display_code,
      old_code: old_code,
      new_code: new_code,
      status: status,
      old_content: old_content,
      new_content: current_content,
      children: children + checkpoints
    }
  end

  def build_unified_checkpoints(current_checkpoints, old_checkpoints)
    # Index checkpoints by text content (match by content, not position)
    current_by_text = {}
    old_by_text = {}

    current_checkpoints.each do |cp|
      text = get_checkpoint_text(cp)
      if text.present?
        current_by_text[text] ||= []
        current_by_text[text] << cp
      end
    end

    old_checkpoints.each do |cp|
      text = get_checkpoint_text(cp)
      if text.present?
        old_by_text[text] ||= []
        old_by_text[text] << cp
      end
    end

    all_texts = (current_by_text.keys + old_by_text.keys).uniq

    all_texts.flat_map do |text|
      current_matches = current_by_text[text] || []
      old_matches = old_by_text[text] || []

      max_count = [ current_matches.length, old_matches.length ].max

      (0...max_count).map do |index|
        current_cp = current_matches[index]
        old_cp = old_matches[index]

        if current_cp && old_cp
          status = checkpoint_content_changed?(old_cp, current_cp) ? DIFF_TYPES[:modified] : DIFF_TYPES[:unchanged]
          build_unified_checkpoint_node(current_cp, old_cp, status)
        elsif current_cp
          build_unified_checkpoint_node(current_cp, nil, DIFF_TYPES[:added])
        else
          build_unified_checkpoint_node(nil, old_cp, DIFF_TYPES[:removed])
        end
      end
    end.compact
  end

  def get_checkpoint_text(checkpoint)
    translations = checkpoint.checklist_item_translations.index_by(&:language_code)
    en_translation = translations["en"] || translations.values.first
    en_translation&.text
  end

  def build_unified_checkpoint_node(current_cp, old_cp, status)
    current_content = current_cp ? build_checkpoint_content(current_cp) : nil
    old_content = old_cp ? build_checkpoint_content(old_cp) : nil

    {
      id: "checkpoint_#{current_cp&.id || old_cp&.id}",
      type: "checkpoint",
      parent_code: current_cp&.clause&.code || old_cp&.clause&.code,
      sort_order: current_cp&.sort_order || old_cp&.sort_order,
      status: status,
      old_content: old_content,
      new_content: current_content,
      children: []
    }
  end

  private

  def build_node_content(node)
    translations = node.clause_translations.index_by(&:language_code)
    en_translation = translations["en"] || translations.values.first
    ar_translation = translations["ar"]

    {
      id: node.id,
      code: node.code,
      title: en_translation&.title || node.code,
      title_ar: ar_translation&.title,
      summary: en_translation&.summary,
      summary_ar: ar_translation&.summary,
      body: en_translation&.body,
      body_ar: ar_translation&.body,
      sort_order: node.sort_order
    }
  end


  def build_checkpoint_content(checkpoint)
    translations = checkpoint.checklist_item_translations.index_by(&:language_code)
    en_translation = translations["en"] || translations.values.first
    ar_translation = translations["ar"]

    {
      id: checkpoint.id,
      item_type: checkpoint.item_type,
      text: en_translation&.text,
      text_ar: ar_translation&.text,
      guidance: en_translation&.guidance,
      guidance_ar: ar_translation&.guidance,
      sort_order: checkpoint.sort_order
    }
  end

  def build_maps(nodes, map)
    return unless nodes.is_a?(Array)

    nodes.each do |node|
      normalized_code = normalize_code(node.code)
      key = normalized_code || node.stable_key || node.id.to_s
      map[key] = node if key.present?

      node.checklist_items.ordered.each do |checkpoint|
        checkpoint_key = "#{normalized_code}_checkpoint_#{checkpoint.sort_order}"
        map[checkpoint_key] = checkpoint if checkpoint_key.present?
      end

      build_maps(node.children.ordered.to_a, map) if node.children.any?
    end
  end

  def normalize_code(code)
    return nil unless code.present?
    code.to_s.gsub("-", ".")
  end






  def checkpoint_content_changed?(old_checkpoint, new_checkpoint)
    # Both are ChecklistItem ActiveRecord objects
    old_translations = old_checkpoint.checklist_item_translations.index_by(&:language_code)
    new_translations = new_checkpoint.checklist_item_translations.index_by(&:language_code)

    old_en = old_translations["en"] || old_translations.values.first
    new_en = new_translations["en"] || new_translations.values.first
    old_ar = old_translations["ar"]
    new_ar = new_translations["ar"]

    # Compare all relevant fields
    (old_checkpoint.item_type != new_checkpoint.item_type) ||
    (old_en&.text != new_en&.text) ||
    (old_ar&.text != new_ar&.text) ||
    (old_en&.guidance != new_en&.guidance) ||
    (old_ar&.guidance != new_ar&.guidance)
  end

  def calculate_summary(diff_tree)
    summary = {
      added_count: 0,
      removed_count: 0,
      modified_count: 0,
      unchanged_count: 0
    }

    count_nodes(diff_tree, summary)
    summary
  end

  def count_nodes(nodes, summary)
    nodes.each do |node|
      case node[:status]
      when "added"
        summary[:added_count] += 1
      when "removed"
        summary[:removed_count] += 1
      when "modified"
        summary[:modified_count] += 1
      when "unchanged"
        summary[:unchanged_count] += 1
      end

      # Recursively count children
      if node[:children].any?
        count_nodes(node[:children], summary)
      end
    end
  end
end
