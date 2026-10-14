class AddMonitorToSystems < ActiveRecord::Migration[4.2]
  def change
    add_column :systems, :monitor, :boolean
    System.all.each do |system|
      system.monitor=true
      system.save
    end
  end
end
