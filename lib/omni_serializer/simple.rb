# frozen_string_literal: true

# Resemples ActiveModel::Serialization as closely as possible.
class OmniSerializer::Simple
  extend Dry::Initializer

  option :query_builder, OmniSerializer::Types::Interface(:call)
  option :evaluator, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :root, OmniSerializer::Types::Bool, default: proc { false }

  # @param value [Object, Array<Object>] The object to serialize.
  # @param with [Class] The resource class to use for serialization.
  # @param context [Hash] The context to use for serialization.
  # @return [Hash] The serialized object.
  def serialize(value, with:, context: {}, **query_options)
    query = query_builder.call(with, **query_options)
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
      traverse_result(placeholder.values).transform_keys { |key| key_formatter.call(key) }
    end
  end

  def with_root(result, resource)
    if result.is_a?(Array)
      { key_formatter.call(resource.type, :plural) => result }
    else
      { key_formatter.call(resource.type, :singular) => result }
    end
  end
end
