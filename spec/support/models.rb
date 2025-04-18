# frozen_string_literal: true

class Post < ActiveRecord::Base
  belongs_to :user
  belongs_to :category, optional: true
  has_many :comments
  has_many :taggings, as: :taggable
  has_many :tags, through: :taggings
end

class User < ActiveRecord::Base
  has_many :posts
  has_many :comments
end

class Category < ActiveRecord::Base
  belongs_to :parent, class_name: 'Category', optional: true
  has_many :children, class_name: 'Category', foreign_key: :parent_id
  has_many :posts
end

class Comment < ActiveRecord::Base
  belongs_to :post
  belongs_to :user
  has_many :taggings, as: :taggable
  has_many :tags, through: :taggings
end

class Tagging < ActiveRecord::Base
  belongs_to :tag
  belongs_to :taggable, polymorphic: true
end

class Tag < ActiveRecord::Base
  has_many :taggings
  has_many :posts, through: :taggings, source: :taggable, source_type: 'Post'
  has_many :comments, through: :taggings, source: :taggable, source_type: 'Comment'
end
