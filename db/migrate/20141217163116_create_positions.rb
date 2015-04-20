class CreatePositions < ActiveRecord::Migration
  def change
    create_table :positions do |t|
      t.bigint :word_id
      t.smallint :position
      t.bigint :event_id
    end
  end
end
