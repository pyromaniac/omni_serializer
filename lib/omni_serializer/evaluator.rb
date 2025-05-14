# frozen_string_literal: true

# Evaluates OmniSerializer::Query by traversing the query tree and resolving the values
# defined in resources. Since this a BFS algorithm, it is able to collect all the promises
# and resolve them later in order to support Dataloader pattern.
class OmniSerializer::Evaluator
  extend Dry::Initializer

  # :nodoc:
  class Placeholder < Dry::Struct
    include OmniSerializer::Inspect.new(:resource, :values)

    attribute :resource, OmniSerializer::Types::Instance(OmniSerializer::Resource).optional
    attribute :values, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)
  end

  # :nodoc:
  class QueueItem < Dry::Struct
    attribute :placeholder, Placeholder
    attribute :query, OmniSerializer::Query
    attribute :value, OmniSerializer::Types::Any
    attribute :path, OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol | OmniSerializer::Types::Integer)
  end

  option :loaders, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Class)

  def call(value, query, context:)
    loaders = OmniSerializer::Loaders.new(@loaders)
    queue = [QueueItem.new(placeholder:, query:, value:, path: [:root])]
    result = nil

    until queue.empty?
      queue.shift => { placeholder:, query: query_level, value:, path: }
      value = value.value! if value.is_a?(Concurrent::Promises::Future)
      value = maybe_wrap(value, placeholder.resource&.object, path, query_level, loaders:, context:)
      result = placeholder if placeholder.resource.nil?

      placeholder.values[query_level.name] = if value.respond_to?(:to_ary)
        value.map.with_index { |item, index| enqueue(queue, item, query_level, path + [index]) }
      else
        enqueue(queue, value, query_level, path)
      end
    end

    result.values[query.name]
  end

  private

  def maybe_wrap(object, parent, path, query, **options)
    return object if query.schema.nil? || object.nil?

    if object.respond_to?(:to_ary)
      if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?
        placeholder(query.schema.resource.new(object, parent:, path:, arguments: query.arguments, **options))
      else
        object.map do |item|
          if query.schema.is_a?(Hash)
            placeholder(query.schema[item.class].resource
              .new(item, parent:, path:, arguments: query.arguments, **options))
          else
            placeholder(query.schema.resource.new(item, parent:, path:, arguments: query.arguments, **options))
          end
        end
      end
    else
      return if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?

      if query.schema.is_a?(Hash)
        placeholder(query.schema[object.class].resource
          .new(object, parent:, path:, arguments: query.arguments, **options))
      else
        placeholder(query.schema.resource.new(object, parent:, path:, arguments: query.arguments, **options))
      end
    end
  end

  def placeholder(resource = nil, values: {})
    Placeholder.new(resource:, values:)
  end

  def enqueue(queue, value, query, path)
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
            query: nested_query,
            path: path + [nested_query.name]
          )
        )
      end
    end

    value
  end
end
