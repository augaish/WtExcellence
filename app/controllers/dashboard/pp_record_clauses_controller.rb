# Clauses are written inside the Documenter by whoever holds the work, so the
# permission is the Documenter's, not the record form's.
class Dashboard::PpRecordClausesController < Dashboard::DocumenterContentController
  before_action :set_clause, only: [ :update, :destroy ]

  def create
    clause = @record.clauses.new(clause_params)
    if clause.save
      back(notice: t("documenter.flash.clause_saved"))
    else
      back(alert: clause.errors.full_messages.to_sentence)
    end
  end

  def update
    if @clause.update(clause_params)
      back(notice: t("documenter.flash.clause_saved"))
    else
      back(alert: @clause.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @clause.destroy
    back(notice: t("documenter.flash.clause_deleted"))
  end

  private

  def set_clause
    @clause = @record.clauses.find_by(id: params[:id])
    back(alert: t("pp_records.flash.not_found")) if @clause.nil?
  end

  def clause_params
    params.require(:pp_record_clause).permit(:parent_id, :position, :title, :body)
  end
end
