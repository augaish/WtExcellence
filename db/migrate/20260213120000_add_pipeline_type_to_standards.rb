# frozen_string_literal: true

class AddPipelineTypeToStandards < ActiveRecord::Migration[7.1]
  def change
    add_column :standards, :pipeline_type, :string, limit: 50, null: true
  end
end
