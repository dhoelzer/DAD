class AddKey2ToDisplay < ActiveRecord::Migration[4.2]
  def change
    add_column :displays, :key2, :string
    add_column :displays, :key2_field, :integer
  end
end
