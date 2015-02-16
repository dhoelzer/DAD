class ChangeWordTextToText < ActiveRecord::Migration
  def change
    change_column :words, :text, :text
  end
end
