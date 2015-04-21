class CreateServices < ActiveRecord::Migration
  def change
    create_table :services, :id => false do |t|
      t.integer :id, :limit => 8
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
