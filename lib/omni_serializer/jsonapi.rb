# frozen_string_literal: true

class OmniSerializer::Jsonapi
  extend Dry::Initializer

  RESERVED_ATTRIBUTES = %i[id type].freeze

  option :query_builder, OmniSerializer::Types::Interface(:call)
  option :evaluator, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)

  def serialize(value, with:, context: {}, params: {})
    query = query_builder.call(with, **params)
    data = evaluator.call(value, query, context:)
    included = collect_linkage(data).except(*top_level_linkage(data))
    result = { data: render_data(data) }
    unless included.empty?
      result[:included] = included.values.map do |placeholder|
        render_resource(placeholder)
      end
    end
    result
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
    members = placeholder.resource.class.members.except(*RESERVED_ATTRIBUTES).values.grep(OmniSerializer::Resource::Member)
    attribute_names = members.select { |member| member.macro == :attribute }.map(&:name)
    meta_names = members.select { |member| member.macro == :meta }.map(&:name)

    data = {
      id: placeholder.resource.id,
      type: type_formatter.call(placeholder.resource.class.type),
      attributes: placeholder.values.slice(*attribute_names).transform_keys { |key| key_formatter.call(key) },
      relationships: render_relationships(placeholder)
    }
    meta = placeholder.values.slice(*meta_names).transform_keys { |key| key_formatter.call(key) }
    data[:meta] = meta unless meta.empty?
    data
  end

  def render_relationships(placeholder)
    associations = placeholder.resource.class.members.values.grep(OmniSerializer::Resource::Association).index_by(&:name)

    associations.to_h do |name, association|
      relationship = if placeholder.values.key?(name)
        { data: relationship_data(placeholder.values[name], association) }
      else
        {}
      end

      [key_formatter.call(name), relationship]
    end
  end

  def relationship_data(value, association)
    return if value.nil?

    if value.is_a?(Array)
      value.map { |item| relationship_data(item, association) }
    elsif value.resource.class.collection?
      value.values[value.resource.class.collection_member.name].map { |item| relationship_data(item, association) }
    else
      { id: value.resource.id, type: type_formatter.call(value.resource.class.type) }
    end
  end
end
