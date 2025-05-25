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
    result = { data: render_data(data) }
    meta = collection_meta(data)
    result[:meta] = meta unless meta.empty?
    result[:included] = render_included(data) if params.key?(:include)
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

  def render_included(data)
    included = collect_included(data).except(*top_level_linkage(data))
    included.values.map { |placeholder| render_resource(placeholder) }
  end

  def collect_included(value)
    queue = value.is_a?(Array) ? [*value] : [value]
    placeholders = {}

    until queue.empty?
      placeholder = queue.shift

      resource = placeholder.resource
      placeholders[[resource.class, resource.id]] = placeholder unless resource.class.collection?

      queue.concat(unused_resource_associations(placeholder, placeholders))
    end

    placeholders
  end

  def unused_resource_associations(placeholder, placeholders)
    resource_associations(placeholder).reject do |associated_placeholder|
      resource = associated_placeholder.resource
      !resource.class.collection? && placeholders.key?([resource.class, resource.id])
    end
  end

  def resource_associations(placeholder)
    placeholder.resource.class.members.values.grep(OmniSerializer::Resource::Association).flat_map do |association|
      Array(placeholder.values[association.name])
    end
  end

  def top_level_linkage(value)
    case value
    in OmniSerializer::Evaluator::Placeholder
      top_level_placeholder_linkage(value)
    in Array
      value.flat_map { |item| top_level_linkage(item) }
    end
  end

  def top_level_placeholder_linkage(placeholder)
    if placeholder.resource.class.collection?
      placeholder.values[placeholder.resource.class.collection_member.name].flat_map { |item| top_level_linkage(item) }
    else
      [[placeholder.resource.class, placeholder.resource.id]]
    end
  end

  def render_data(value)
    if value.is_a?(Array)
      value.map { |item| render_resource(item) }
    elsif value.resource.class.collection?
      render_collection(value)
    elsif value.nil?
      nil
    else
      render_resource(value)
    end
  end

  def render_collection(placeholder)
    placeholder.values[placeholder.resource.class.collection_member.name].map { |item| render_resource(item) }
  end

  def render_resource(placeholder)
    members = placeholder.resource.class.members.except(*RESERVED_ATTRIBUTES)
      .values.grep(OmniSerializer::Resource::Member)
    attribute_names = members.select { |member| member.macro == :attribute }.map(&:name)
    meta_names = members.select { |member| member.macro == :meta }.map(&:name)
    render_resource_members(placeholder, attribute_names, meta_names)
  end

  def render_resource_members(placeholder, attribute_names, meta_names)
    data = render_resource_data(placeholder, attribute_names)
    meta = placeholder.values.slice(*meta_names).transform_keys { |key| key_formatter.call(key) }
    data[:meta] = meta unless meta.empty?
    data
  end

  def render_resource_data(placeholder, attribute_names)
    {
      id: placeholder.resource.id.to_s,
      type: type_formatter.call(placeholder.resource.class.type),
      attributes: placeholder.values.slice(*attribute_names).transform_keys { |key| key_formatter.call(key) },
      relationships: render_relationships(placeholder)
    }
  end

  def render_relationships(placeholder)
    placeholder.resource.class.members.values.grep(OmniSerializer::Resource::Association).to_h do |association|
      relationship = if placeholder.values.key?(association.name)
        relationship_members(placeholder.values[association.name])
      else
        {}
      end

      [key_formatter.call(association.name), relationship]
    end
  end

  def relationship_members(value)
    return { data: nil } if value.nil?

    data = relationship_data(value)
    meta = collection_meta(value)

    meta.empty? ? { data: } : { data:, meta: }
  end

  def relationship_data(value)
    if value.is_a?(Array)
      value.map { |item| relationship_linkage(item) }
    elsif value.resource.class.collection?
      value.values[value.resource.class.collection_member.name].map { |item| relationship_linkage(item) }
    else
      relationship_linkage(value)
    end
  end

  def relationship_linkage(placeholder)
    { id: placeholder.resource.id.to_s, type: type_formatter.call(placeholder.resource.class.type) }
  end

  def collection_meta(placeholder)
    return {} unless placeholder.is_a?(OmniSerializer::Evaluator::Placeholder) && placeholder.resource.class.collection?

    placeholder.values.filter_map do |name, value|
      member = placeholder.resource.class.members[name]

      next unless member in OmniSerializer::Resource::Member(macro: :meta)

      [key_formatter.call(name), maybe_deep_transform_keys(member, value)]
    end.to_h
  end

  def maybe_deep_transform_keys(member, value)
    return value unless member in OmniSerializer::Resource::Member(transform_keys: true)

    OmniSerializer::Utils.deep_transform_keys(value) { |key| key_formatter.call(key) }
  end
end
