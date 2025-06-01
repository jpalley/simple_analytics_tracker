class CreateErrorRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :error_requests do |t|
      t.integer :status_code, null: false
      t.string :request_method, null: false
      t.string :path, null: false
      t.text :user_agent
      t.string :ip_address
      t.text :referer
      t.text :error_message
      t.text :request_params
      t.datetime :timestamp, null: false

      t.timestamps
    end

    add_index :error_requests, :status_code
    add_index :error_requests, :timestamp
    add_index :error_requests, [ :status_code, :timestamp ]
  end
end
