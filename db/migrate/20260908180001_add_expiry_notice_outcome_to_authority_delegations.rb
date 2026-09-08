class AddExpiryNoticeOutcomeToAuthorityDelegations < ActiveRecord::Migration[8.0]
  def change
    # The stamp said a delegation had been examined; it did not say what
    # happened. A delegation with nobody to tell is now recorded as such, and
    # is examined again once someone is there to tell.
    add_column :authority_delegations, :expiry_notice_outcome, :string, limit: 20
  end
end
