class AddGeneratedIndexToEvent < ActiveRecord::Migration
  def change
    add_index :events, :generated
  end
end
