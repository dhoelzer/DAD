class AddGeneratedIndexToEventsWords < ActiveRecord::Migration[4.2]
  def change
    add_index :events_words, :generated
  end
end
