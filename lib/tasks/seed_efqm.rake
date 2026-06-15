namespace :efqm do
  desc "Create an EFQM standard with clauses and checkpoints (like a super admin PDF upload)"
  task seed: :environment do
    ActiveRecord::Base.transaction do
      code = "EFQM-#{SecureRandom.hex(3).upcase}"

      standard = Standard.create!(code: code, is_primary: false, pipeline_type: "efqm")
      StandardTranslation.create!(standard: standard, language_code: "en", name: "EFQM Model #{code}", description: "European Foundation for Quality Management excellence model")
      StandardTranslation.create!(standard: standard, language_code: "ar", name: "نموذج EFQM #{code}", description: "نموذج المؤسسة الأوروبية لإدارة الجودة")

      version = StandardVersion.create!(standard: standard, version_label: "2025", status: "published", published_at: Time.current)

      criteria = [
        {
          code: "1", title_en: "Direction", title_ar: "التوجيه", points: 100,
          subs: [
            { code: "1.1", title_en: "Define Purpose and Vision", title_ar: "تحديد الهدف والرؤية", points: 50,
              checks: [
                { en: "The organisation has a clear purpose statement that inspires and provides direction.", ar: "لدى المنظمة بيان هدف واضح يلهم ويوفر التوجيه." },
                { en: "Leaders develop the mission, vision and values and act as role models.", ar: "يطور القادة الرسالة والرؤية والقيم ويعملون كنماذج يحتذى بها." },
              ]
            },
            { code: "1.2", title_en: "Drive the Culture and Values", title_ar: "تعزيز الثقافة والقيم", points: 50,
              checks: [
                { en: "Leaders reinforce a culture of excellence with the organisation's people.", ar: "يعزز القادة ثقافة التميز مع أفراد المنظمة." },
                { en: "Ethics and organisational values guide behaviour at all levels.", ar: "تحكم الأخلاق والقيم التنظيمية السلوك على جميع المستويات." },
                { en: "Leaders ensure flexibility and manage change effectively.", ar: "يضمن القادة المرونة ويديرون التغيير بفعالية." },
              ]
            },
          ]
        },
        {
          code: "2", title_en: "Execution", title_ar: "التنفيذ", points: 100,
          subs: [
            { code: "2.1", title_en: "Engage Stakeholders", title_ar: "إشراك أصحاب المصلحة", points: 50,
              checks: [
                { en: "The needs and expectations of stakeholders are understood and balanced.", ar: "يتم فهم احتياجات وتوقعات أصحاب المصلحة والتوازن بينها." },
                { en: "Partnerships and suppliers are managed for mutual benefit.", ar: "تتم إدارة الشراكات والموردين لتحقيق المنفعة المتبادلة." },
              ]
            },
            { code: "2.2", title_en: "Create Value", title_ar: "إنشاء القيمة", points: 50,
              checks: [
                { en: "Products and services are designed and managed to create optimum value.", ar: "يتم تصميم المنتجات والخدمات وإدارتها لإنشاء أقصى قيمة." },
                { en: "Products and services are delivered and managed to meet customer needs.", ar: "يتم تقديم المنتجات والخدمات وإدارتها لتلبية احتياجات العملاء." },
              ]
            },
          ]
        },
        {
          code: "3", title_en: "Results", title_ar: "النتائج", points: 100,
          subs: [
            { code: "3.1", title_en: "Stakeholder Perceptions", title_ar: "تصورات أصحاب المصلحة", points: 50,
              checks: [
                { en: "These are the stakeholders' perceptions of the organisation, obtained through surveys, focus groups, and reviews.", ar: "هذه هي تصورات أصحاب المصلحة عن المنظمة، يتم الحصول عليها من خلال الاستطلاعات ومجموعات التركيز والمراجعات." },
                { en: "Customer satisfaction metrics are tracked and show positive trends.", ar: "يتم تتبع مقاييس رضا العملاء وتظهر اتجاهات إيجابية." },
              ]
            },
            { code: "3.2", title_en: "Strategic & Operational Performance", title_ar: "الأداء الاستراتيجي والتشغيلي", points: 50,
              checks: [
                { en: "Key financial and non-financial outcomes are achieved and show positive trends.", ar: "يتم تحقيق النتائج المالية وغير المالية الرئيسية وتظهر اتجاهات إيجابية." },
                { en: "Performance indicators demonstrate sustained improvement.", ar: "تُظهر مؤشرات الأداء تحسنًا مستدامًا." },
                { en: "Organisational agility and responsiveness are evidenced.", ar: "يتم إثبات مرونة المنظمة واستجابتها." },
              ]
            },
          ]
        },
      ]

      criteria.each do |crit|
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
      puts "  #{clause_count} clauses (#{terminal_count} terminal), #{checkpoint_count} checkpoints"
    end
  end
end
