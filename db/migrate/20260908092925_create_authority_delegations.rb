class CreateAuthorityDelegations < ActiveRecord::Migration[8.0]
  def change
    # A grant of an authority from one position to another.
    #
    # From and to are organizational units, never users: «تفويض الصلاحيات للمنصب
    # وليس للشخص… تتوقف صلاحيات الشخص بتركه المنصب». A delegation therefore
    # survives a change of postholder, which is the whole point of it.
    create_table :authority_delegations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :authority, type: :uuid, null: false, foreign_key: true
      t.references :from_org_unit, type: :uuid, null: false, foreign_key: { to_table: :org_units }
      t.references :to_org_unit, type: :uuid, null: false, foreign_key: { to_table: :org_units }

      # permanent — until revoked
      # temporary — for a stated period, typically leave or travel
      # acting     — during a تكليف, whose scope the acting decision defines
      t.string :kind, limit: 20, null: false, default: "temporary"

      # A delegate may be given less than the holder carries, never more.
      t.decimal :limit_amount, precision: 15, scale: 2

      t.date :valid_from
      t.date :valid_to

      t.string :status, limit: 20, null: false, default: "draft"

      # The written decision. «يجب أن يكون التفويض موثقًا كتابيًا عن طريق أحد
      # القنوات الرسمية» — a delegation with no decision behind it is hearsay.
      t.references :decision_record, type: :uuid, null: true, foreign_key: { to_table: :pp_records }

      # Sub-delegation: «بإمكان صاحب الصلاحية تفويض … لمستوى وظيفي أدنى بموافقة
      # مانح الصلاحية الأصلية»، with accountability remaining with the original
      # holder.
      t.references :parent_delegation, type: :uuid, null: true, foreign_key: { to_table: :authority_delegations }
      t.references :grantor_approved_by, type: :uuid, null: true, foreign_key: { to_table: :users }
      t.datetime :grantor_approved_at

      t.text :reason
      t.references :revoked_by, type: :uuid, null: true, foreign_key: { to_table: :users }
      t.datetime :revoked_at
      t.text :revocation_reason

      t.timestamps
    end

    add_index :authority_delegations, [ :company_id, :status ]
    add_index :authority_delegations, [ :authority_id, :valid_to ]
  end
end
