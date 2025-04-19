# frozen_string_literal: true

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Base.logger = Logger.new(File::NULL)

ActiveRecord::Schema.define do
  create_table :posts do |t|
    t.column :user_id, :integer
    t.column :category_id, :integer
    t.column :title, :string
    t.column :content, :jsonb
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
