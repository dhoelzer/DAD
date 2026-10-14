class AddGeneratedIndexToEvent < ActiveRecord::Migration[4.2]
  def change
    add_index :events, :generated
  end
end
