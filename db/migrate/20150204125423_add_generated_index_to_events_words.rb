class AddGeneratedIndexToEventsWords < ActiveRecord::Migration
  def change
    add_index :events_words, :generated
  end
end
