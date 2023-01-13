class CreateUsers < ActiveRecord::Migration[6.1]
  def change
    create_table :users do |t|
      t.string :username
      t.string :user_id
      t.boolean :approved

      t.timestamps
    end
  end
end
