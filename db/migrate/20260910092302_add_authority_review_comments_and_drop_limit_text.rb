# Reviewers comment per authority during the approval round, and the owner
# answers each comment with accept or reject and a reason. The limit column
# goes: a threshold is written inside the authority's own wording now.
class AddAuthorityReviewCommentsAndDropLimitText < ActiveRecord::Migration[8.0]
  def change
    create_table :authority_review_comments, id: :uuid do |t|
      t.references :matrix, type: :uuid, null: false, foreign_key: { to_table: :pp_records }
      t.references :authority, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.text :body, null: false
      t.string :decision, limit: 20
      t.text :reply
      t.references :replied_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :replied_at
      t.timestamps
    end

    remove_column :authorities, :limit_text, :string, limit: 250
  end
end
