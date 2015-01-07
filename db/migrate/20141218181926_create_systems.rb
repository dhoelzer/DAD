class CreateSystems < ActiveRecord::Migration
  def change
    create_table :systems do |t|
      t.string :address
      t.string :name
      t.text :description
      t.string :administrator
      t.string :contact_email

      t.timestamps
    end
  end
end
