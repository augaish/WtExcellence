# frozen_string_literal: true

class AddReceiveNotificationsOnEmailToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :receive_notifications_on_email, :boolean, null: false, default: true
  end
end

