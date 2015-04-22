class CreateIndicesOnEventsWords < ActiveRecord::Migration
  def change
    create_table :indices_on_events_words do |t|
      add_index :events_words, :event_id
      add_index :events_words, :word_id
    end
  end
end
