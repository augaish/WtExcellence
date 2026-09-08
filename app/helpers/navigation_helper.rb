module NavigationHelper
  # The single definition behind both the desktop sidebar and the mobile menu.
  # Keeping one source means a destination can never be permitted on desktop but
  # missing on mobile, and that a module a super admin has disabled disappears
  # from both. Sections with no visible items are dropped so neither menu
  # renders a bare heading.
  def nav_sections
    [
      { title: t("main_menu"), items: nav_main_items },
      { title: t("quality"), items: nav_quality_items },
      { title: t("pp.title"), hint: t("pp.full_title"), items: nav_pp_items },
      { title: t("governance"), items: nav_governance_items },
      { title: t("settings"), items: nav_settings_items }
    ].reject { |section| section[:items].empty? }
  end

  private

  # Items are built with this helper so every caller produces the same shape.
  # `active` is evaluated here rather than in the views, which is what let the
  # two menus drift apart in the first place.
  def nav_item(label:, path:, icon:, active:)
    { label: label, path: path, icon: icon, active: active }
  end

  def nav_main_items
    items = []
    if current_user&.super_admin? || current_user&.delegated_admin? || current_user&.company_user.present?
      items << nav_item(label: t("overview"), path: dashboard_overview_path,
        icon: "overview-icon.svg", active: request.path.include?("overview"))
    end
    if nav_module?(:library)
      items << nav_item(label: t("library"), path: library_path,
        icon: "library-icon.svg", active: request.path.start_with?("/library"))
    end
    if nav_module?(:org_structure)
      items << nav_item(label: t("org_structure.title"), path: dashboard_org_units_path,
        icon: "account-management-icon.svg", active: request.path.include?("org_units"))
    end
    items
  end

  def nav_quality_items
    items = []
    if nav_module?(:standards)
      items << nav_item(label: t("standards"), path: standards_path,
        icon: "standards-icon.svg", active: request.path.start_with?("/standards"))
    end
    if nav_module?(:capa) && !(current_user&.super_admin? || current_user&.delegated_admin?)
      items << nav_item(label: t("capa_management"), path: dashboard_capa_management_path,
        icon: "capa-management-icon.svg", active: request.path.include?("capa_management"))
    end
    items
  end

  def nav_pp_items
    return [] unless nav_module?(:pp)

    [
      nav_item(label: t("process_architecture.title"), path: dashboard_pp_processes_path,
        icon: "standards-icon.svg", active: request.path.include?("pp_processes")),
      nav_item(label: t("pp_records.title"), path: dashboard_pp_records_path,
        icon: "library-icon.svg", active: request.path.include?("pp_records") || request.path.include?("pp_packages")),
      nav_item(label: t("documenter.title"), path: dashboard_documenter_path,
        icon: "calendar-03.png", active: request.path.include?("documenter")),
      nav_item(label: t("evaluation.title"), path: dashboard_process_evaluations_path,
        icon: "score-start-icon.svg", active: request.path.include?("evaluation"))
    ]
  end

  def nav_governance_items
    items = []
    if current_user&.can_manage_risks? && module_enabled_for_current?(:risk)
      items << nav_item(label: t("risk_management"), path: dashboard_risk_management_index_path,
        icon: "score-start-icon.svg",
        active: request.path.include?("risk_management") || request.path.include?("risk_workspaces"))
    end
    if current_user&.can_manage_vendors? && module_enabled_for_current?(:vendors)
      items << nav_item(label: t("vendor_management"), path: dashboard_vendors_path,
        icon: "account-management-icon.svg", active: request.path.include?("vendors"))
    end
    if current_user&.can_manage_commitments? && module_enabled_for_current?(:commitments)
      items << nav_item(label: t("customer_commitments"), path: dashboard_customer_commitments_path,
        icon: "calendar-03.png", active: request.path.include?("customer_commitments"))
    end
    items
  end

  def nav_settings_items
    items = []
    if current_user&.can_manage_ai_instructions? && module_enabled_for_current?(:ai_instructions)
      items << nav_item(label: t("ai_instructions"), path: dashboard_ai_instructions_path,
        icon: "AI_logo.png", active: request.path.include?("ai_instructions"))
    end
    if current_user&.can_manage_tools? && module_enabled_for_current?(:tools)
      items << nav_item(label: t("tool_setup"), path: tools_path,
        icon: "tool-setup-icon.svg", active: request.path.include?("tools"))
    end
    if current_user&.super_admin? || current_user&.delegated_admin?
      items << nav_item(label: t("credit_changes"), path: dashboard_credit_changes_path,
        icon: "account-management-icon.svg", active: request.path.include?("credit_changes"))
    end
    if current_user&.super_admin? || current_user&.delegated_admin? || current_user&.company_user&.has_admin_privileges?
      items << nav_item(label: t("branding.title"), path: dashboard_branding_path,
        icon: "general-settings-icon.svg", active: request.path.include?("branding"))
    end
    if current_user&.super_admin? || current_user&.delegated_admin? || current_user&.company_user&.company_admin?
      items << nav_item(label: t("account_management"), path: dashboard_account_management_path,
        icon: "account-management-icon.svg", active: request.path.include?("account_management"))
    end
    if current_user&.company_user.present? && !current_user&.company_contributor?
      items << nav_item(label: t("ai_usage"), path: dashboard_ai_insights_path,
        icon: "overview-icon.svg", active: request.path.start_with?("/dashboard/ai_insights"))
    end
    items << nav_item(label: t("general_settings"), path: dashboard_general_settings_path,
      icon: "general-settings-icon.svg", active: request.path.include?("general_settings"))
    items
  end

  # Risk managers only ever see the Governance section, so every module outside
  # it is hidden from them regardless of the company's module settings.
  def nav_module?(key)
    module_enabled_for_current?(key) && !current_user&.risk_manager_only?
  end
end
