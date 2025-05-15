# frozen_string_literal: true

# Using PG instead of in-memory SQLite3 since the Evaluator algorithm utilizes promises
# executed concurrently and in-memory SQLite3 doesn't support multiple connections.
MAINTAINANCE_DB = '/postgres'
database_url = URI.parse(ENV.fetch('DATABASE_URL', 'postgres://localhost/omni_serializer'))
ActiveRecord::Base.establish_connection(database_url.merge(MAINTAINANCE_DB).to_s)
ActiveRecord::Base.connection.recreate_database(database_url.path.delete_prefix('/'))
ActiveRecord::Base.establish_connection(database_url.to_s)
ActiveRecord::Base.logger = Logger.new(File::NULL)

ActiveRecord::Schema.define do
  create_table :posts do |t|
    t.column :user_id, :integer
    t.column :category_id, :integer
    t.column :title, :string
    t.column :content, :jsonb
    t.column :published_at, :datetime
  end

  create_table :users do |t|
    t.column :name, :string
  end

  create_table :categories do |t|
    t.column :name, :string
    t.column :parent_id, :integer
  end

  create_table :comments do |t|
    t.column :user_id, :integer
    t.column :post_id, :integer
    t.column :body, :text
    t.column :deleted_at, :datetime
  end

  create_table :taggings do |t|
    t.column :tag_id, :integer
    t.column :taggable_id, :integer
    t.column :taggable_type, :string
  end

  create_table :tags do |t|
    t.column :name, :string
  end
end
