class AddGeneratedToEventsWords < ActiveRecord::Migration[4.2]
  def change
    add_column :events_words, :generated, :datetime, :default => Time.now, :null => false
  end
end
