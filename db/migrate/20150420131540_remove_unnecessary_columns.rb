class RemoveUnnecessaryColumns < ActiveRecord::Migration
  def change
    remove_column :words, :created_at
    remove_column :words, :updated_at
    remove_column :positions, :created_at
    remove_column :positions, :updated_at
    remove_column :statistics, :created_at
    remove_column :statistics, :updated_at
    
  end
end
