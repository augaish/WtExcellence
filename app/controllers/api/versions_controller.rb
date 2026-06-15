class Api::VersionsController < ApplicationController
  def clauses
    version = StandardVersion.find(params[:id])

    clauses = version.clauses.includes(:clause_translations, :checklist_items, :children)
                     .root_clauses
                     .ordered
                     .map do |clause|
      serialize_clause(clause)
    end

    render json: { clauses: clauses }
  end

  private

  def serialize_clause(clause)
    {
      id: clause.id,
      code: clause.code,
      title: clause.clause_translations.where(language_code: "en").first&.title || clause.code,
      children: clause.children.ordered.map { |child| serialize_clause(child) },
      checkpoints: clause.checklist_items.ordered.map { |item|
        item.checklist_item_translations.where(language_code: "en").first&.text
      }.compact
    }
  end
end
