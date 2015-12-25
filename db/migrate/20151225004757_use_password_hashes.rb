class UsePasswordHashes < ActiveRecord::Migration
  def change
    User.all.each do |user|
      user.store_password(user.password)
      user.save
    end
  end
end
