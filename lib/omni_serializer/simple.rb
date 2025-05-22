# frozen_string_literal: true

# Resemples ActiveModel::Serialization as closely as possible.
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
  # @param params [Hash] The params to use for serialization.
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
    return value unless member.is_a?(OmniSerializer::Resource::Member) && member.transform_keys

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
