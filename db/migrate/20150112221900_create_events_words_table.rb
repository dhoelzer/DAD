class CreateEventsWordsTable < ActiveRecord::Migration
  def change
    create_join_table :events, :words do |t|
      t.index :event_id
      t.index :word_id
    end
  end
end
