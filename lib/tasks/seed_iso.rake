namespace :iso do
  desc "Create an ISO 9001 standard with clauses, checkpoints, and a Yes/No tool"
  task seed: :environment do
    ActiveRecord::Base.transaction do
      code = "ISO9001-#{SecureRandom.hex(3).upcase}"

      standard = Standard.create!(code: code, is_primary: false, pipeline_type: "iso9001")
      StandardTranslation.create!(standard: standard, language_code: "en", name: "ISO 9001 #{code}", description: "Quality Management System requirements")
      StandardTranslation.create!(standard: standard, language_code: "ar", name: "ايزو 9001 #{code}", description: "متطلبات نظام إدارة الجودة")

      version = StandardVersion.create!(standard: standard, version_label: "2015", status: "published", published_at: Time.current)

      # ── ISO Tool (single "Fulfillment" category, Yes/No scoring) ───
      tool = Tool.create!(
        name: "ISO 9001 Assessment Tool (#{code})",
        description: "Simple Yes/No compliance assessment for ISO 9001",
        business_rules: {}
      )
      ToolTranslation.create!(tool: tool, language_code: "en", name: tool.name, description: tool.description)
      ToolTranslation.create!(tool: tool, language_code: "ar", name: "أداة تقييم ايزو 9001", description: "تقييم الامتثال بنعم/لا لمعيار ايزو 9001")

      # Single checkpoint → one text area per checkpoint box
      fulfillment_cp = tool.checkpoints.create!(name: "Fulfillment", display_order: 1)
      ToolCheckpointTranslation.create!(tool_checkpoint: fulfillment_cp, language_code: "en", name: "Fulfillment")
      ToolCheckpointTranslation.create!(tool_checkpoint: fulfillment_cp, language_code: "ar", name: "الاستيفاء")

      # Single subcheckpoint with Multiple Choice (Yes/No)
      compliance_sub = fulfillment_cp.subcheckpoints.create!(
        name: "Compliance",
        description: "Is the requirement fulfilled?",
        scoring_type: "Multiple Choice",
        multiple_choice_options: [
          { "text" => "Yes", "weight" => 100 },
          { "text" => "Partial", "weight" => 50 },
          { "text" => "No", "weight" => 0 }
        ],
        weight: nil,
        is_cap: false,
        display_order: 1
      )
      ToolSubcheckpointTranslation.create!(tool_subcheckpoint: compliance_sub, language_code: "en", name: "Compliance", description: "Is the requirement fulfilled?", multiple_choice_options: [{ "text" => "Yes", "weight" => 100 }, { "text" => "Partial", "weight" => 50 }, { "text" => "No", "weight" => 0 }])
      ToolSubcheckpointTranslation.create!(tool_subcheckpoint: compliance_sub, language_code: "ar", name: "الامتثال", description: "هل تم استيفاء المتطلب؟", multiple_choice_options: [{ "text" => "نعم", "weight" => 100 }, { "text" => "جزئي", "weight" => 50 }, { "text" => "لا", "weight" => 0 }])

      # ── ISO 9001 Clause Hierarchy ──────────────────────────────────
      clauses_data = [
        {
          code: "4", title_en: "Context of the Organization", title_ar: "سياق المنظمة", points: 100,
          subs: [
            { code: "4.1", title_en: "Understanding the Organization and its Context", title_ar: "فهم المنظمة وسياقها", points: 50,
              checks: [
                { en: "The organization determines external and internal issues relevant to its purpose.", ar: "تحدد المنظمة القضايا الخارجية والداخلية ذات الصلة بغرضها." },
                { en: "The organization monitors and reviews information about these issues.", ar: "تراقب المنظمة وتراجع المعلومات حول هذه القضايا." },
              ]
            },
            { code: "4.2", title_en: "Understanding Needs and Expectations of Interested Parties", title_ar: "فهم احتياجات وتوقعات الأطراف المعنية", points: 50,
              checks: [
                { en: "The organization determines interested parties relevant to the QMS.", ar: "تحدد المنظمة الأطراف المعنية ذات الصلة بنظام إدارة الجودة." },
                { en: "The organization determines the requirements of these interested parties.", ar: "تحدد المنظمة متطلبات هذه الأطراف المعنية." },
              ]
            },
          ]
        },
        {
          code: "5", title_en: "Leadership", title_ar: "القيادة", points: 100,
          subs: [
            { code: "5.1", title_en: "Leadership and Commitment", title_ar: "القيادة والالتزام", points: 50,
              checks: [
                { en: "Top management demonstrates leadership and commitment to the QMS.", ar: "تُظهر الإدارة العليا القيادة والالتزام بنظام إدارة الجودة." },
                { en: "Top management ensures the quality policy and objectives are established.", ar: "تضمن الإدارة العليا وضع سياسة الجودة والأهداف." },
              ]
            },
            { code: "5.2", title_en: "Quality Policy", title_ar: "سياسة الجودة", points: 50,
              checks: [
                { en: "Top management establishes and maintains a quality policy.", ar: "تضع الإدارة العليا سياسة الجودة وتحافظ عليها." },
                { en: "The quality policy is communicated and understood within the organization.", ar: "يتم التواصل بشأن سياسة الجودة وفهمها داخل المنظمة." },
              ]
            },
          ]
        },
        {
          code: "6", title_en: "Planning", title_ar: "التخطيط", points: 100,
          subs: [
            { code: "6.1", title_en: "Actions to Address Risks and Opportunities", title_ar: "إجراءات لمعالجة المخاطر والفرص", points: 50,
              checks: [
                { en: "The organization determines risks and opportunities that need to be addressed.", ar: "تحدد المنظمة المخاطر والفرص التي يجب معالجتها." },
                { en: "The organization plans actions to address these risks and opportunities.", ar: "تخطط المنظمة لإجراءات لمعالجة هذه المخاطر والفرص." },
              ]
            },
            { code: "6.2", title_en: "Quality Objectives and Planning", title_ar: "أهداف الجودة والتخطيط", points: 50,
              checks: [
                { en: "The organization establishes quality objectives at relevant functions and levels.", ar: "تضع المنظمة أهداف الجودة على المستويات والوظائف ذات الصلة." },
                { en: "Quality objectives are consistent with the quality policy and measurable.", ar: "تتسق أهداف الجودة مع سياسة الجودة وتكون قابلة للقياس." },
              ]
            },
          ]
        },
      ]

      clauses_data.each do |crit|
        parent = Clause.create!(
          standard_version: version, parent: nil,
          code: crit[:code], sort_order: crit[:code].to_i,
          allocated_points: crit[:points], base_points: crit[:points]
        )
        ClauseTranslation.create!(clause: parent, language_code: "en", title: crit[:title_en])
        ClauseTranslation.create!(clause: parent, language_code: "ar", title: crit[:title_ar])

        crit[:subs].each do |sub|
          child = Clause.create!(
            standard_version: version, parent: parent,
            code: sub[:code], sort_order: sub[:code].split(".").last.to_i,
            allocated_points: sub[:points], base_points: sub[:points]
          )
          ClauseTranslation.create!(clause: child, language_code: "en", title: sub[:title_en])
          ClauseTranslation.create!(clause: child, language_code: "ar", title: sub[:title_ar])

          # Link tool to terminal clause
          ToolClause.create!(tool: tool, clause: child)

          sub[:checks].each_with_index do |check, ci|
            item = ChecklistItem.create!(clause: child, item_type: "requirement", code: "#{sub[:code]}-#{ci + 1}", sort_order: ci + 1)
            ChecklistItemTranslation.create!(checklist_item: item, language_code: "en", text: check[:en])
            ChecklistItemTranslation.create!(checklist_item: item, language_code: "ar", text: check[:ar])
          end
        end
      end

      clause_count = version.clauses.count
      terminal_count = version.clauses.select(&:leaf?).count
      checkpoint_count = ChecklistItem.joins(:clause).where(clauses: { standard_version_id: version.id }).count

      puts "Created standard: #{code}"
      puts "  Tool: #{tool.name}"
      puts "  #{clause_count} clauses (#{terminal_count} terminal), #{checkpoint_count} checkpoints"
      puts "  Scoring: Yes/Partial/No (Multiple Choice)"
    end
  end
end
