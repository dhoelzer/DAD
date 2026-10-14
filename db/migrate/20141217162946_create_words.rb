class CreateWords < ActiveRecord::Migration[4.2]
  def change
    create_table :words do |t|
      t.string :text
    end
  end
end
