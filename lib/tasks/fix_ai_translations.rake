namespace :translations do
  desc "Fix AI-generated translations that incorrectly have needs_review: true"
  task fix_ai_review_flags: :environment do
    puts "Fixing AI-generated translations..."

    clause_count = ClauseTranslation.where(needs_review: true).update_all(needs_review: false)
    checkpoint_count = ChecklistItemTranslation.where(needs_review: true).update_all(needs_review: false)

    puts "Fixed #{clause_count} clause translations"
    puts "Fixed #{checkpoint_count} checkpoint translations"
    puts "Done!"
  end
end
