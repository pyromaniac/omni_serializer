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
    loaders.aggregate(Comment.active, :post_id, :count).load(object.id)
  end
  meta :tag_names do
    tags.then { |tags| tags.map(&:name) }
  end
  has_one :post_author, resource: 'UserResource' do
    loaders.record(User.all).load(object.user_id) if object.user_id
  end
  has_many :comments, resource: 'CommentCollectionResource' do
    loaders.collection(Comment.active, :post_id).load(object.id)
  end
  has_many :taggings, resource: 'TaggingResource' do
    loaders.collection(Tagging.where(taggable_type: 'Post'), :taggable_id).load(object.id)
  end
  has_many :tags, resource: 'TagResource' do
    loaders.collection(
      Tag.joins(:taggings).where(taggings: { taggable_type: 'Post' }),
      %i[taggings taggable_id]
    ).load(object.id)
  end
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
    loaders.aggregate(Comment.active, :user_id, :count).load(object.id)
  end
  meta :posts_count do
    loaders.aggregate(Post.published(context.fetch(:now)), :user_id, :count).load(object.id)
  end
  has_many :comments, resource: 'CommentCollectionResource' do
    loaders.collection(Comment.active, :user_id).load(object.id)
  end
  has_many :posts, resource: 'PostCollectionResource' do
    loaders.collection(Post.published(context.fetch(:now)), :user_id).load(object.id)
  end
end

class CategoryResource < BaseResource
  attribute :category_name do
    object.name
  end
  has_one :parent, resource: 'CategoryResource' do
    loaders.record(Category.all).load(object.parent_id) if object.parent_id
  end
  has_many :children, resource: 'CategoryResource' do
    loaders.collection(Category.all, :parent_id).load(object.id)
  end
  has_many :posts, resource: 'PostCollectionResource' do
    loaders.collection(Post.published(context.fetch(:now)), :category_id).load(object.id)
  end
end

class CommentResource < BaseResource
  attribute :comment_body do
    object.body
  end
  has_one :post, resource: 'PostResource' do
    loaders.record(Post.all).load(object.post_id)
  end
  has_one :comment_author, resource: 'UserResource' do
    loaders.record(User.all).load(object.user_id) if object.user_id
  end
  has_many :taggings, resource: 'TaggingResource' do
    loaders.collection(Tagging.where(taggable_type: 'Comment'), :taggable_id).load(object.id)
  end
  has_many :tags, resource: 'TagResource' do
    loaders.collection(
      Tag.joins(:taggings).where(taggings: { taggable_type: 'Comment' }),
      %i[taggings taggable_id]
    ).load(object.id)
  end
end

class CommentCollectionResource < BaseCollectionResource
  collection resource: 'CommentResource'
  meta :total_count do
    object.count
  end
end

class TaggingResource < BaseResource
  has_one :tag, resource: 'TagResource'
  has_one :taggable, resource: { Post => 'PostResource', Comment => 'CommentResource' } do
    case object.taggable_type
    when 'Post'
      loaders.record(Post.published(context.fetch(:now))).load(object.taggable_id)
    when 'Comment'
      loaders.record(Comment.active).load(object.taggable_id)
    end
  end
end

class TagResource < BaseResource
  attribute :tag_name do
    object.name
  end
  has_many :taggings, resource: 'TaggingResource' do
    loaders.collection(Tagging.all, :tag_id).load(object.id)
  end
  has_many :taggables, resource: { Post => 'PostResource', Comment => 'CommentResource' } do
    loaders.collection(Post.joins(:taggings), %i[taggings tag_id]).load(object.id).then do |posts|
      loaders.collection(Comment.joins(:taggings), %i[taggings tag_id]).load(object.id).then do |comments|
        posts + comments
      end
    end
  end
end
