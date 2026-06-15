# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :commentable, polymorphic: true, null: false, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid, index: true
      t.uuid :parent_id
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, [:commentable_type, :commentable_id]
    add_index :comments, :parent_id
  end
end
