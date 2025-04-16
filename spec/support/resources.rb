# frozen_string_literal: true

class BaseResource < OmniSerializer::Resource
  type { name.delete_suffix('Resource').underscore }
  attribute :id
end

class BaseCollectionResource < OmniSerializer::Resource
  type { name.delete_suffix('Resource').underscore }
end

class PostResource < BaseResource
  attribute :post_title do
    object.title
  end
  attribute :post_content do
    object.content
  end
  meta :comments_count do
    object.comments.count
  end
  has_one :post_author, resource: 'UserResource' do
    object.user
  end
  has_many :comments, resource: 'CommentCollectionResource'
  has_many :taggings, resource: 'TaggingResource'
  has_many :tags, resource: 'TagResource'
end

class PostCollectionResource < BaseCollectionResource
  collection resource: 'PostResource'
  meta :total_count do
    object.count
  end
end

class UserResource < BaseResource
  attribute :user_name do
    object.name
  end
  meta :comments_count do
    object.comments.count
  end
  meta :posts_count do
    object.posts.count
  end
  has_many :comments, resource: 'CommentCollectionResource'
  has_many :posts, resource: 'PostCollectionResource'
end

class CommentResource < BaseResource
  attribute :comment_body do
    object.body
  end
  has_one :post, resource: 'PostResource'
  has_one :comment_author, resource: 'UserResource' do
    object.user
  end
  has_many :taggings, resource: 'TaggingResource'
  has_many :tags, resource: 'TagResource'
end

class CommentCollectionResource < BaseCollectionResource
  collection resource: 'CommentResource'
  meta :total_count do
    object.count
  end
end

class TaggingResource < BaseResource
  has_one :tag, resource: 'TagResource'
  has_one :taggable, resource: { Post => 'PostResource', Comment => 'CommentResource' }
end

class TagResource < BaseResource
  attribute :tag_name do
    object.name
  end
  has_one :tagging, resource: 'TaggingResource'
  has_many :taggables, resource: { Post => 'PostResource', Comment => 'CommentResource' } do
    object.posts + object.comments
  end
end
