class CreateSystems < ActiveRecord::Migration
  def change
    create_table :systems, :id => false do |t|
      t.integer :id, :limit => 8      
      t.string :address
      t.string :name
      t.text :description
      t.string :administrator
      t.string :contact_email

      t.timestamps
    end
  end
end
