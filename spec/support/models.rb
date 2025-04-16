# frozen_string_literal: true

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments
  has_many :taggings, as: :taggable
  has_many :tags, through: :taggings
end

class User < ActiveRecord::Base
  has_many :posts
  has_many :comments
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
