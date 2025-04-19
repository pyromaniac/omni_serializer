# frozen_string_literal: true

class OmniSerializer::Evaluator
  extend Dry::Initializer

  class Placeholder < Dry::Struct
    include OmniSerializer::Inspect.new(:resource, :values)

    attribute :resource, OmniSerializer::Types::Any.optional
    attribute :values, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)
  end

  class QueueItem < Dry::Struct
    attribute :placeholder, Placeholder
    attribute :query, OmniSerializer::Query
    attribute :value, OmniSerializer::Types::Any
  end

  option :loaders, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Class)

  def call(value, query, context:)
    cache = OmniSerializer::Cache.new
    loaders = OmniSerializer::Loaders.new(@loaders)
    queue = [QueueItem.new(placeholder:, query:, value:)]
    result = nil

    until queue.empty?
      queue.shift => { placeholder:, query: query_level, value: }
      value = value.sync if value.is_a?(Promise)
      value = maybe_wrap(value, query_level, cache:, loaders:, context:)
      result = placeholder if placeholder.resource.nil?

      placeholder.values[query_level.name] = if value.respond_to?(:to_ary)
        value.map { |item| enqueue(queue, item, query_level) }
      else
        enqueue(queue, value, query_level)
      end
    end

    result.values[query.name]
  end

  private

  def maybe_wrap(object, query, **options)
    return object if query.schema.nil? || object.nil?

    if object.respond_to?(:to_ary)
      if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?
        placeholder(query.schema.resource.new(object, arguments: query.arguments, **options))
      else
        object.map do |item|
          if query.schema.is_a?(Hash)
            placeholder(query.schema[item.class].resource.new(item, arguments: query.arguments, **options))
          else
            placeholder(query.schema.resource.new(item, arguments: query.arguments, **options))
          end
        end
      end
    else
      return if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?

      if query.schema.is_a?(Hash)
        placeholder(query.schema[object.class].resource.new(object, arguments: query.arguments, **options))
      else
        placeholder(query.schema.resource.new(object, arguments: query.arguments, **options))
      end
    end
  end

  def placeholder(resource = nil, values: {})
    Placeholder.new(resource:, values:)
  end

  def enqueue(queue, value, query)
    if value.is_a?(Placeholder)
      members = if query.schema.is_a?(Hash)
        query.schema[value.resource.object.class].members
      else
        query.schema&.members || []
      end
      members.each do |nested_query|
        queue.push(
          QueueItem.new(
            placeholder: value,
            value: value.resource.public_send(nested_query.name, **nested_query.arguments),
            query: nested_query
          )
        )
      end
    end

    value
  end
end
