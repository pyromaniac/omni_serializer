# frozen_string_literal: true

class BaseResource < OmniSerializer::Resource
  type { name.delete_suffix('Resource').underscore }
  attribute :id
end

class PaginatedCollectionResource < OmniSerializer::Resource
  type { name.delete_suffix('Resource').underscore }

  def self.default_page(page = nil)
    page ? @page = page : (@page || 1)
  end

  def self.default_per_page(per_page = nil)
    per_page ? @per_page = per_page : (@per_page || 10)
  end

  meta :current_page do
    current_page
  end

  meta :pagination, expose: true, transform_keys: true do
    total_count.then do |count|
      { total_count: count, total_pages: (count / per_page.to_f).ceil, current_page: }
    end
  end

  private

  def total_count
    raise NotImplementedError
  end

  def current_page
    arguments.dig(:page, :number)&.to_i || self.class.default_page
  end

  def per_page
    arguments.dig(:page, :size)&.to_i || self.class.default_per_page
  end
end

class CommentCollectionResource < PaginatedCollectionResource
  PARENT_FOREIGN_KEY_MAPPING = {
    Post => :post_id,
    User => :user_id
  }.freeze

  collection resource: 'CommentResource' do
    if parent
      loaders.collection(filtered_scope, PARENT_FOREIGN_KEY_MAPPING.fetch(parent.class)).load(parent.id)
    else
      filtered_scope
    end
  end

  private

  def total_count
    if parent
      loaders.aggregate(filtered_scope, PARENT_FOREIGN_KEY_MAPPING.fetch(parent.class), :count).load(parent.id)
    else
      filtered_scope.count
    end
  end

  def filtered_scope
    arguments.dig(:filter, :active) ? object.active : object
  end
end

class CommentResource < BaseResource
  attribute :comment_body do
    object.body
  end
  has_one :post, resource: 'PostResource' do
    loaders.record(Post).load(object.post_id)
  end
  has_one :comment_author, resource: 'UserResource' do
    loaders.record(User).load(object.user_id) if object.user_id
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

class PostCollectionResource < PaginatedCollectionResource
  PARENT_FOREIGN_KEY_MAPPING = {
    Category => :category_id,
    User => :user_id
  }.freeze

  collection resource: 'PostResource' do
    if parent
      loaders.collection(filtered_scope, PARENT_FOREIGN_KEY_MAPPING.fetch(parent.class)).load(parent.id)
    else
      filtered_scope
    end
  end

  private

  def total_count
    if parent
      loaders.aggregate(filtered_scope, PARENT_FOREIGN_KEY_MAPPING.fetch(parent.class), :count).load(parent.id)
    else
      filtered_scope.count
    end
  end

  def filtered_scope
    arguments.dig(:filter, :published) ? object.published(context.fetch(:now)) : object
  end
end

class PostResource < BaseResource
  attribute :post_title do
    object.title
  end
  attribute :post_content do
    object.content
  end
  meta :tag_names do
    tags.then { |tags| tags.map(&:name) }
  end
  has_one :post_author, resource: 'UserResource' do
    loaders.record(User).load(object.user_id) if object.user_id
  end
  has_many :active_comments, resource: 'CommentCollectionResource' do
    Comment.active
  end
  has_many :taggings, resource: 'TaggingResource' do
    loaders.collection(Tagging.where(taggable_type: 'Post'), :taggable_id).load(object.id)
  end
  has_many :tags, resource: 'TagResource' do
    loaders.collection(
      Tag.order(:name).joins(:taggings).where(taggings: { taggable_type: 'Post' }),
      %i[taggings taggable_id]
    ).load(object.id)
  end
end

class CategoryResource < BaseResource
  attribute :category_name do
    object.name
  end
  has_one :parent, resource: 'CategoryResource' do
    loaders.record(Category).load(object.parent_id) if object.parent_id
  end
  has_many :children, resource: 'CategoryResource' do
    loaders.collection(Category.order(:name), :parent_id).load(object.id)
  end
  has_many :published_posts, resource: 'PostCollectionResource' do
    Post.published(context.fetch(:now))
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
    loaders.collection(Tagging, :tag_id).load(object.id)
  end
  has_many :taggables, resource: { Post => 'PostResource', Comment => 'CommentResource' } do
    loaders.collection(Post.joins(:taggings), %i[taggings tag_id]).load(object.id).zip(
      loaders.collection(Comment.joins(:taggings), %i[taggings tag_id]).load(object.id)
    ).then { |posts, comments| posts + comments }
  end
end

class UserResource < BaseResource
  attribute :user_name do
    object.name
  end
  meta :post_tag_names do
    loaders.collection(Tag.joins(:posts), %i[posts user_id]).load(object.id).then { |tags| tags.map(&:name) }
  end
  meta :comment_tag_names do
    loaders.collection(Tag.joins(:comments), %i[comments user_id]).load(object.id).then { |tags| tags.map(&:name) }
  end
  has_many :comments, resource: 'CommentCollectionResource' do
    Comment.all
  end
  has_many :posts, resource: 'PostCollectionResource' do
    Post.all
  end
end
