class CreateSearches < ActiveRecord::Migration[4.2]
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
