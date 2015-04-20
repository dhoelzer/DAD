class CreateSearches < ActiveRecord::Migration
  def change
    create_table :searches do |t|
      t.text :string
      t.index :user_id
      t.text :description
      t.string :short_description

      t.timestamps
    end
  end
end
