class CreateWords < ActiveRecord::Migration
  def change
    create_table :words, :id => false do |t|
      t.integer :id, :limit => 8
      t.string :text
    end
  end
end
