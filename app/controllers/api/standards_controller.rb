class Api::StandardsController < ApplicationController
  # GET /api/standards/:id/terminal_clauses (optional: tool_id for "already assigned" display)
  # Returns root-level clauses with terminal counts and assignment info.
  # Non–super-admin users may only access standards assigned to their company.
  def terminal_clauses
    standard = Standard.find(params[:id])
    tool_id = params[:tool_id] # Optional: current tool ID to exclude from "already assigned" check

    # Restrict standard access: super admin and delegated admin can see any standard; others only if assigned to their company
    unless current_user&.super_admin? || current_user&.delegated_admin?
      company = current_user&.company_user&.company
      unless company && standard_assigned_to_company?(standard, company)
        render json: { error: "Access denied" }, status: :forbidden
        return
      end
    end

    # Get the latest version of the standard
    latest_version = standard.standard_versions.order(created_at: :desc).first

    unless latest_version
      render json: { clauses: [] }
      return
    end

    # Get root/top-level clauses from the latest version
    clauses = latest_version.clauses
                            .includes(:clause_translations, :tool_clause, :children)
                            .root_clauses
                            .ordered
                            .map do |clause|
      # Check if any terminal clause under this top-level clause is already assigned to another tool
      terminal_clauses = get_all_terminal_clauses(clause)
      already_assigned_clauses = terminal_clauses.select do |tc|
        tc.tool_clause.present? && 
        (tool_id.blank? || tc.tool_clause.tool_id.to_s != tool_id.to_s)
      end
      
      already_assigned = already_assigned_clauses.any?
      assigned_tool = already_assigned ? Tool.find_by(id: already_assigned_clauses.first.tool_clause.tool_id) : nil
      
      {
        id: clause.id,
        code: clause.code,
        title: clause.title("en") || clause.code,
        terminal_count: terminal_clauses.count,
        base_points: clause.base_points || 0,
        already_assigned: already_assigned,
        assigned_to_tool_name: assigned_tool&.name
      }
    end

    render json: { clauses: clauses }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Standard not found" }, status: :not_found
  end

  private

  def standard_assigned_to_company?(standard, company)
    CompanyStandard.exists?(
      standard_id: standard.id,
      company_id: company.id,
      status: "active"
    )
  end

  # Recursively get all terminal (leaf) clauses under a given clause
  def get_all_terminal_clauses(clause)
    if clause.leaf?
      [ clause ]
    else
      clause.children.flat_map { |child| get_all_terminal_clauses(child) }
    end
  end
end
