# frozen_string_literal: true

# A lightweight serializer that renders resources as plain Ruby hashes.
# It resembles ActiveModel::Serialization, but query selection is driven by a
# small params DSL:
# - `only`: selects members for the current resource. Accepts a symbol, an
#   array of symbols, or a hash mapping member names to member arguments:
#   `:post_title`, `%i[id post_title]`, or `{ post_title: { prefix: 'Draft: ' } }`.
# - `except`: removes members from the current resource defaults. Accepts a
#   symbol or an array of symbols: `:post_content` or `%i[id post_content]`.
# - `extra`: adds non-exposed members to the current resource. Accepts the same
#   formats as `only`: `:tag_names`, `%i[tag_names pagination]`, or
#   `{ tag_names: { locale: :th } }`.
# - `include`: includes associations. Accepts a symbol, an array, or a nested
#   hash whose values use the same DSL as the current level:
#   `:post_author`, `%i[post_author tags]`, or
#   `{ active_comments: { only: :comment_body, include: :comment_author } }`.
# - `collection`: only meaningful when the current resource is a collection
#   resource. Its value is a hash of query options for the collection wrapper
#   itself, while `only` and `include` at the same level still apply to each
#   item in the collection: `{ collection: { only: :current_page } }`.
# - `types`: only meaningful for polymorphic associations. Its value is a hash
#   keyed by resource type identifiers, where each value is a nested query hash
#   for that resource: `{ types: { 'post' => { include: :tags } } }`.
# Any other params keys are forwarded to the current resource as `arguments`,
# for example `{ page: { number: 2 }, filter: { active: true } }`.
class OmniSerializer::Simple
  extend Dry::Initializer

  option :query_builder, OmniSerializer::Types::Interface(:call)
  option :evaluator, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :root, OmniSerializer::Types::Bool, default: proc { false }
  option :collection_key, OmniSerializer::Types::Symbol, default: proc { :collection }

  def self.build(loaders:, **)
    new(
      query_builder: OmniSerializer::Simple::QueryBuilder.new,
      evaluator: OmniSerializer::Evaluator.new(loaders:),
      **
    )
  end

  # @param value [Object, Array<Object>] The object to serialize.
  # @param with [Class] The resource class to use for serialization.
  # @param params [Hash] Query options for shaping the serialized tree.
  #   Reserved keys are `only`, `except`, `extra`, `include`, `collection`,
  #   and `types`. String keys are normalized to symbols. All other keys become
  #   runtime arguments for the current resource and are exposed through
  #   `resource.arguments`.
  # @param context [Hash] The context to use for serialization.
  # @return [Hash] The serialized object.
  def serialize(value, with:, params: {}, context: {})
    query = query_builder.call(with, **params)
    result = traverse_result(evaluator.call(value, query, context:))
    root ? with_root(result, with) : result
  end

  private

  def traverse_result(value)
    case value
    when OmniSerializer::Evaluator::Placeholder
      traverse_placeholder(value)
    when Array
      value.map { |item| traverse_result(item) }
    when Hash
      value.transform_values { |item| traverse_result(item) }
    else
      value
    end
  end

  def traverse_placeholder(placeholder)
    collection_member = placeholder.resource.class.collection_member if placeholder.resource.class.collection?
    if collection_member && placeholder.values.keys == [collection_member.name]
      traverse_result(placeholder.values[collection_member.name])
    else
      traverse_result(traverse_placeholder_values(placeholder))
    end
  end

  def traverse_placeholder_values(placeholder)
    resource_class = placeholder.resource.class
    placeholder.values.to_h do |name, value|
      name = collection_key if resource_class.collection? && resource_class.collection_member.name == name
      value = maybe_deep_transform_keys(resource_class.members[name], value)

      [key_formatter.call(name), value]
    end
  end

  def maybe_deep_transform_keys(member, value)
    return value unless member in OmniSerializer::Resource::Member(transform_keys: true)

    OmniSerializer::Utils.deep_transform_keys(value) { |key| key_formatter.call(key) }
  end

  def with_root(result, resource)
    if result.is_a?(Array)
      { key_formatter.call(resource.type, :plural) => result }
    else
      { key_formatter.call(resource.type, :singular) => result }
    end
  end
end
