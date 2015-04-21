class CreateSearches < ActiveRecord::Migration
  def change
    create_table :searches do |t|
      t.text :string
      t.integer :user_id, :limit => 8
      t.text :description
      t.string :short_description

      t.timestamps
    end
  end
end
