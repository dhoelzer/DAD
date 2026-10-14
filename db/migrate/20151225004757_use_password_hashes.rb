class UsePasswordHashes < ActiveRecord::Migration[4.2]
  def change
    User.all.each do |user|
      user.store_password(user.password)
      user.save
    end
  end
end
