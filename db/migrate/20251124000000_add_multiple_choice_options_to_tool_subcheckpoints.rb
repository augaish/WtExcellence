class AddMultipleChoiceOptionsToToolSubcheckpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_subcheckpoints, :multiple_choice_options, :jsonb, default: []
  end
end

