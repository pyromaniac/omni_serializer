# frozen_string_literal: true

# Main JSONAPI serialization/deserialization entry point.
# Should be memoized in the scope of the API version and then used in every controller action.
class OmniSerializer::Jsonapi
  extend Dry::Initializer

  # A JSONAPI error object structure.
  class Error < Dry::Struct
    attribute? :id, OmniSerializer::Types::String
    attribute? :links, OmniSerializer::Types::Hash.schema(
      about?: OmniSerializer::Types::String,
      type?: OmniSerializer::Types::String
    ).strict.constrained(filled: true)
    attribute? :status, OmniSerializer::Types::Coercible::String
    attribute? :code, OmniSerializer::Types::Coercible::String
    attribute? :title, OmniSerializer::Types::String
    attribute? :detail, OmniSerializer::Types::String
    attribute? :source, OmniSerializer::Types::Hash.schema(
      pointer?: OmniSerializer::Types::String,
      parameter?: OmniSerializer::Types::String,
      header?: OmniSerializer::Types::String
    ).strict.constrained(filled: true)
    attribute? :meta, OmniSerializer::Types::Hash
      .map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any).constrained(filled: true)
  end

  RESERVED_ATTRIBUTES = %i[id type].freeze

  option :query_builder, OmniSerializer::Types::Interface(:call)
  option :evaluator, OmniSerializer::Types::Interface(:call)
  option :deserializer, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)

  def self.build(loaders:, key_formatter:, type_formatter:, **)
    missing_key_formatter = OmniSerializer::NameFormatter.new(
      inflector: key_formatter.inflector,
      casing: :snake,
      symbolize: true
    )

    new(
      query_builder: OmniSerializer::Jsonapi::QueryBuilder
        .build(missing_key_formatter:, key_formatter:, type_formatter:),
      evaluator: OmniSerializer::Evaluator.new(loaders:),
      deserializer: OmniSerializer::Jsonapi::Deserializer.new(missing_key_formatter:, key_formatter:, type_formatter:),
      key_formatter:,
      type_formatter:,
      **
    )
  end

  def serialize(value, with:, params: {}, context: {})
    query = query_builder.call(with, **params)
    data = evaluator.call(value, query, context:)
    included = collect_linkage(data).except(*top_level_linkage(data))
    result = { data: render_data(data) }
    meta = collection_meta(data)
    result[:meta] = meta unless meta.empty?
    if params.key?(:include)
      result[:included] = included.values.map do |placeholder|
        render_resource(placeholder)
      end
    end
    result
  end

  def deserialize(params, with:)
    deserializer.call(with, params[:data])
  end

  def errors(*errors)
    errors = errors.flatten(1).map do |error|
      error = error.error_data if error.respond_to?(:error_data)
      error = Error.new(error) unless error.is_a?(Error)
      error.to_h
    end

    { errors: }
  end

  private

  def collect_linkage(value)
    queue = value.is_a?(Array) ? [*value] : [value]
    placeholders = {}

    until queue.empty?
      placeholder = queue.shift

      enqueue = if placeholder.resource.class.collection?
        placeholder.values[placeholder.resource.class.collection_member.name]
      else
        placeholders[[placeholder.resource.class, placeholder.resource.id]] = placeholder
        placeholder.resource.class.members.values.grep(OmniSerializer::Resource::Association).flat_map do |association|
          Array.wrap(placeholder.values[association.name])
        end
      end

      queue.concat(enqueue.reject do |item|
        !item.resource.class.collection? && placeholders[[item.resource.class, item.resource.id]]
      end)
    end

    placeholders
  end

  def top_level_linkage(value)
    case value
    in OmniSerializer::Evaluator::Placeholder
      if value.resource.class.collection?
        value.values[value.resource.class.collection_member.name].flat_map { |item| top_level_linkage(item) }
      else
        [[value.resource.class, value.resource.id]]
      end
    in Array
      value.flat_map { |item| top_level_linkage(item) }
    end
  end

  def render_data(value)
    if value.is_a?(Array)
      value.map { |item| render_resource(item) }
    elsif value.resource.class.collection?
      value.values[value.resource.class.collection_member.name].map { |item| render_resource(item) }
    elsif value.nil?
      nil
    else
      render_resource(value)
    end
  end

  def render_resource(placeholder)
    members = placeholder.resource.class.members.except(*RESERVED_ATTRIBUTES)
      .values.grep(OmniSerializer::Resource::Member)
    attribute_names = members.select { |member| member.macro == :attribute }.map(&:name)
    meta_names = members.select { |member| member.macro == :meta }.map(&:name)

    data = {
      id: placeholder.resource.id.to_s,
      type: type_formatter.call(placeholder.resource.class.type),
      attributes: placeholder.values.slice(*attribute_names).transform_keys { |key| key_formatter.call(key) },
      relationships: render_relationships(placeholder)
    }
    meta = placeholder.values.slice(*meta_names).transform_keys { |key| key_formatter.call(key) }
    data[:meta] = meta unless meta.empty?
    data
  end

  def render_relationships(placeholder)
    placeholder.resource.class.members.values.grep(OmniSerializer::Resource::Association).to_h do |association|
      relationship = if placeholder.values.key?(association.name)
        relationship_data(placeholder.values[association.name])
      else
        {}
      end

      [key_formatter.call(association.name), relationship]
    end
  end

  def relationship_data(value)
    return { data: nil } if value.nil?

    data = if value.is_a?(Array)
      value.map { |item| relationship_linkage(item) }
    elsif value.resource.class.collection?
      value.values[value.resource.class.collection_member.name].map { |item| relationship_linkage(item) }
    else
      relationship_linkage(value)
    end
    meta = collection_meta(value)

    meta.empty? ? { data: } : { data:, meta: }
  end

  def relationship_linkage(placeholder)
    { id: placeholder.resource.id.to_s, type: type_formatter.call(placeholder.resource.class.type) }
  end

  def collection_meta(placeholder)
    return {} unless placeholder.is_a?(OmniSerializer::Evaluator::Placeholder) && placeholder.resource.class.collection?

    placeholder.values.except(*placeholder.resource.class.collection_member.name).filter_map do |name, value|
      member = placeholder.resource.class.members[name]

      next unless member.is_a?(OmniSerializer::Resource::Member) && member.macro == :meta

      value = OmniSerializer::Utils.deep_transform_keys(value) { |key| key_formatter.call(key) }
      [key_formatter.call(name), value]
    end.to_h
  end
end
