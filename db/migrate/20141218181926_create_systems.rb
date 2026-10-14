class CreateSystems < ActiveRecord::Migration[4.2]
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
