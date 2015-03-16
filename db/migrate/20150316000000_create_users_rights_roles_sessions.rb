class CreateUsersRightsRolesSessions < ActiveRecord::Migration
  # Create all of the database tables and such in one migration
  # Imported from previous project
  # TODO: User's password is currently not hashed at all.
  
  def change
    create_table :users do |t|
      t.string :username
      t.string :password
      t.string :first
      t.string :last
      t.integer :attempts
      t.datetime :last_attempt
      t.datetime :lastlogon

      t.timestamps null: false
    end
    create_table :rights_roles do |t|
      t.integer :right_id
      t.integer :role_id
    end
    create_table :rights do |t|
      t.string :name
      t.string :description
    end
    create_table :roles_users do |t|
      t.integer :role_id
      t.integer :user_id
    end
    create_table :roles do |t|
      t.string :name
      t.string :description
    end
    create_table :sessions do |t|
      t.string :session_hash
      t.integer :user_id
      t.datetime :expiry

      t.timestamps null: false
    end

  end
end
