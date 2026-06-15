# frozen_string_literal: true

module PdfPipeline
  class BlockDeduplicator
    def self.deduplicate(blocks)
      # 1. Same-id duplicates: keep the middle one
      id_order = blocks.map { |b| b["id"] }.uniq
      by_id = blocks.group_by { |b| b["id"] }
      after_id_dedup = id_order.filter_map do |id|
        group = by_id[id]
        next nil if group.nil? || group.empty?
        group[group.length / 2] # middle block (0-based)
      end
      same_id_skipped = blocks.length - after_id_dedup.length

      # 2. Reversed-ID handling (e.g. RTL 1-2 vs 2-1)
      seen_ids = Set.new
      deduplicated = []
      skipped_count = same_id_skipped

      after_id_dedup.each do |block|
        id = block["id"]
        parent_id = block["parent_id"]

        if handle_reversed_id?(id, parent_id, seen_ids, deduplicated)
          skipped_count += 1
          next
        end

        seen_ids.add(id)
        deduplicated << block
      end

      Rails.logger.info "Deduplication: kept #{deduplicated.length}, skipped #{skipped_count} duplicates"
      deduplicated
    end

    private

    # Returns true if this is a reversed duplicate that should be skipped
    def self.handle_reversed_id?(id, parent_id, seen_ids, deduplicated)
      return false unless id.include?("-")

      reversed_id = reverse_id(id)
      return false unless reversed_id && seen_ids.include?(reversed_id)

      expected_parent = id.split("-")[0]
      existing = deduplicated.find { |b| b["id"] == reversed_id }

      if existing && parent_id == expected_parent && existing["parent_id"] != expected_parent
        deduplicated.delete(existing)
        seen_ids.delete(reversed_id)
        Rails.logger.debug "Replaced #{reversed_id} with #{id} (better parent match)"
        false
      else
        true
      end
    end

    def self.reverse_id(id)
      parts = id.split("-")
      return nil unless parts.length == 2 && parts.all? { |p| p.match?(/^\d+$/) }
      "#{parts[1]}-#{parts[0]}"
    end
  end
end
