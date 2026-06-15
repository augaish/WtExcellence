# frozen_string_literal: true

module PdfPipeline
  module IdHelper
    def normalize_id_for_sorting(id)
      return [0] if id.nil? || id.to_s.empty?
      id_str = id.to_s
      normalized = id_str.gsub("-", ".")
      parts = normalized.split(".").map do |part|
        numeric_part = part.match(/^\d+/)
        numeric_part ? numeric_part[0].to_i : 0
      end
      parts
    end

    def transform_id_format(id)
      return id if id.nil?
      id.to_s.gsub("-", ".")
    end
  end
end
