class AddGeneratedToEventsWords < ActiveRecord::Migration
  def change
    add_column :events_words, :generated, :datetime, :default => Time.now, :null => false
  end
end
