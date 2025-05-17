# frozen_string_literal: true

# Evaluates OmniSerializer::Query by traversing the query tree and resolving the values
# defined in resources. Since this a BFS algorithm, it is able to collect all the promises
# and resolve them later in order to support Dataloader pattern.
class OmniSerializer::Evaluator
  extend Dry::Initializer

  REQUEUED = Object.new

  # :nodoc:
  class Placeholder < Dry::Struct
    include OmniSerializer::Inspect.new(:resource, :values)

    attribute :resource, OmniSerializer::Types::Interface(:object, :evaluate, :evaluate?).optional
    attribute :values, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)

    def self.build(resource = nil, values: {})
      new(resource:, values:)
    end
  end

  # :nodoc:
  class QueueItem < Dry::Struct
    attribute :placeholder, Placeholder
    attribute :value, OmniSerializer::Types::Any
    attribute :query, OmniSerializer::Query
    attribute :path, OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol | OmniSerializer::Types::Integer)
    attribute :requeued, OmniSerializer::Types::Bool
  end

  option :loaders, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Class)

  def call(value, root_query, context:)
    loaders = OmniSerializer::Loaders.new(@loaders)
    queue = [QueueItem.new(placeholder: Placeholder.build, value:, query: root_query, path: [], requeued: false)]
    result = nil

    until queue.empty?
      queue_item = queue.shift
      value = resolve_or_requeue_promise(queue, queue_item)

      next if REQUEUED.equal?(value)

      result = queue_item.placeholder if queue_item.placeholder.resource.nil?
      wrap_evaluate_and_enqueue(queue, queue_item, value, loaders:, context:)
    end

    result.values[root_query.name]
  end

  private

  def resolve_or_requeue_promise(queue, queue_item)
    queue_item => { value:, requeued: }

    return value unless value.is_a?(Concurrent::Promises::Future)

    if requeued
      value.value!
    else
      value.touch
      queue.push(queue_item.new(requeued: true))
      REQUEUED
    end
  end

  def wrap_evaluate_and_enqueue(queue, queue_item, value, **)
    queue_item => { placeholder:, query:, path: }

    return if placeholder.resource && !placeholder.resource.evaluate?(query.name)

    value = maybe_wrap(value, query, parent: placeholder.resource&.object, path:, **)
    placeholder.values[query.name] = evaluate_and_enqueue(queue, value, query)
  end

  def evaluate_and_enqueue(queue, value, query)
    if value.respond_to?(:to_ary)
      value.map { |item| enqueue(queue, item, query) }
    else
      enqueue(queue, value, query)
    end
  end

  def maybe_wrap(object, query, **)
    return object if query.schema.nil? || object.nil?

    if object.respond_to?(:to_ary)
      wrap_collection(object, query, **)
    else
      return if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?

      wrap_object(object, query, **)
    end
  end

  def wrap_collection(collection, query, path:, **)
    if query.schema.is_a?(OmniSerializer::Query::ResourceSchema) && query.schema.resource.collection?
      wrap_object(collection, query, path:, **)
    else
      collection.map.with_index { |item, index| wrap_object(item, query, path: path + [index], **) }
    end
  end

  def wrap_object(object, query, path:, **)
    query => { schema:, arguments: }

    if schema.is_a?(Hash)
      schema = schema.fetch(object.class) do
        raise "No schema found for #{object.class}, only #{schema.keys.join(', ')} are allowed, path: #{path.join('.')}"
      end
    end

    Placeholder.build(schema.resource.new(object, arguments:, path:, **))
  end

  def enqueue(queue, value, query)
    if value.is_a?(Placeholder)
      members = if query.schema.is_a?(Hash)
        query.schema[value.resource.object.class].members
      else
        query.schema&.members || []
      end
      members.each do |nested_query|
        queue.push(build_queue_item(value, nested_query))
      end
    end

    value
  end

  def build_queue_item(value, query)
    QueueItem.new(
      placeholder: value,
      value: value.resource.evaluate(query.name, **query.arguments),
      query:,
      path: value.resource.path + [query.name],
      requeued: false
    )
  end
end
