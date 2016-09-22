class CreatePreferences < ActiveRecord::Migration
  def change
    create_table :preferences do |t|
      t.integer :user_id
      t.integer :liveEventsDisplayed
      t.string :dashboardElements

      t.timestamps null: false
    end
  end
end
