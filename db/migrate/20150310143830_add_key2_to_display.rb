class AddKey2ToDisplay < ActiveRecord::Migration
  def change
    add_column :displays, :key2, :string
    add_column :displays, :key2_field, :smallint
  end
end
