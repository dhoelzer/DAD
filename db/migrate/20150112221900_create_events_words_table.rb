class CreateEventsWordsTable < ActiveRecord::Migration
  def change
    create_join_table :events, :words do |t|
      t.integer :event_id, :limit => 8
      t.integer :word_id, :limit => 8
    end
  end
end
