# frozen_string_literal: true

# Converts JSONAPI request data into a flat hash of attributes and ids
# Suitable for passing to operations.
class OmniSerializer::Jsonapi::Deserializer
  extend Dry::Initializer

  ROOT_POINTERS = { [] => '/data', [:id] => '/data/id', [:type] => '/data/type' }.freeze

  # Holds the converted params and their mapping to the original data.
  class Result < Dry::Struct
    attribute :params, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)
    attribute :pointers, OmniSerializer::Types::Hash.map(
      OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol | OmniSerializer::Types::Integer),
      OmniSerializer::Types::String.constrained(format: %r{\A/})
    )
  end

  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)

  def call(resource_class, data)
    type = type_formatter.call(resource_class.type)
    validate_root_data!(data, type)

    members, associations = format_members(resource_class)
    attributes, attribute_pointers = deserialize_attributes(type, members, associations, data[:attributes] || {})
    relationships, relationship_pointers = deserialize_relationships(type, associations, data[:relationships] || {})

    params = { **attributes, **relationships }
    pointers = { **ROOT_POINTERS, **attribute_pointers, **relationship_pointers }

    params[:id] = data[:id] if data.key?(:id)

    Result.new(params:, pointers:)
  end

  private

  def format_members(resource_class)
    [
      resource_class.members.values
        .grep(OmniSerializer::Resource::Member)
        .index_by { |member| key_formatter.call(member.name) },
      resource_class.members.values
        .grep(OmniSerializer::Resource::Association)
        .index_by { |member| key_formatter.call(member.name) }
    ]
  end

  def deserialize_attributes(type, members, associations, attributes)
    mapping = attributes.transform_keys do |key|
      if associations[key.to_s]
        raise OmniSerializer::JsonapiError.new(
          detail: "Relationship `#{key}` on `#{type}` given as an attribute, please move it under `relationships`.",
          status: 400,
          source: { pointer: "/data/attributes/#{key}" }
        )
      end

      member = members[key]
      pointer = "/data/attributes/#{key}"

      [member&.name || missing_key_formatter.call(key).to_sym, pointer]
    end

    [mapping.transform_keys(&:first), mapping.keys.to_h.transform_keys { |key| [key] }]
  end

  def deserialize_relationships(type, associations, relationships)
    mapping = relationships.map do |key, value|
      association = associations[key.to_s]
      pointer = "/data/relationships/#{key}"

      unless association
        raise OmniSerializer::JsonapiError.new(
          detail: "Relationship `#{key}` is not defined on `#{type}`, " \
            "valid relationships are: `#{associations.keys.join('`, `')}`.",
          status: 400,
          source: { pointer: }
        )
      end

      relationship_params(association, key, value, pointer:)
    end

    mapping.each_with_object([{}, {}]) do |(attributes, pointers), (result_attributes, result_pointers)|
      result_attributes.merge!(attributes)
      result_pointers.merge!(pointers)
    end
  end

  def relationship_params(association, key, value, pointer:)
    association_types = resolve_association_types(association)
    pointer = "#{pointer}/data"

    if association.collection
      data = validate_collection_data!(key, value, pointer:)
      collection_relationship_params(association, association_types, key, data, pointer:)
    else
      data = validate_singular_data!(key, association_types, value, pointer:)
      singular_relationship_params(association, association_types, data, pointer:)
    end
  end

  def resolve_association_types(association)
    if !association.polymorphic? && association.resolved_resource.collection?
      association = association.resolved_resource.collection_member
    end

    association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }
    remap_association_types(association, association_types)
  end

  def remap_association_types(association, association_types)
    if association.polymorphic?
      entity_map = association.resolved_resource.invert
      association_types.transform_values { |resource_class| entity_map[resource_class].name }
    else
      association_types
    end
  end

  def collection_relationship_params(association, association_types, key, data, pointer:)
    data.each.with_index do |datum, index|
      validate_collection_datum!(key, datum, association_types, pointer: "#{pointer}/#{index}")
    end

    if association.polymorphic?
      polymorphic_collection_relationship_params(association, association_types, data, pointer:)
    else
      id_key = :"#{missing_key_formatter.call(association.name, :singular)}_ids"

      [
        { id_key => data.map { |datum| datum[:id] } },
        {
          [id_key] => pointer,
          **data.size.times.to_h { |index| [[id_key, index], "#{pointer}/#{index}/id"] }
        }
      ]
    end
  end

  def polymorphic_collection_relationship_params(association, association_types, data, pointer:)
    [
      {
        association.name => data.map do |datum|
          { id: datum[:id], type: association_types[datum[:type]] }
        end
      },
      {
        [association.name] => pointer,
        **data.size.times.flat_map do |index|
          [
            [[association.name, index], "#{pointer}/#{index}"],
            [[association.name, index, :id], "#{pointer}/#{index}/id"],
            [[association.name, index, :type], "#{pointer}/#{index}/type"]
          ]
        end.to_h
      }
    ]
  end

  def singular_relationship_params(association, association_types, data, pointer:)
    id_key = :"#{association.name}_id"
    type_key = :"#{association.name}_type"

    if data.nil?
      [{ id_key => nil }, { [id_key] => pointer }]
    elsif association.polymorphic?
      [
        {
          id_key => data[:id],
          type_key => association_types.fetch(data[:type])
        },
        { [id_key] => "#{pointer}/id", [type_key] => "#{pointer}/type" }
      ]
    else
      [{ id_key => data[:id] }, { [id_key] => "#{pointer}/id" }]
    end
  end

  def validate_type!(data, valid_types, pointer: nil)
    return if valid_types.include?(data[:type])

    raise OmniSerializer::JsonapiError.new(
      detail: "Invalid type given: `#{data[:type]}`, valid types are: `#{valid_types.join('`, `')}`.",
      status: 409,
      source: { pointer: "#{pointer}/type" }
    )
  end

  def validate_root_data!(data, type)
    pointer = '/data'

    if data.is_a?(Hash) && (data.key?(:id) ? (data in { id: String, type: String }) : (data in { type: String }))
      validate_type!(data, [type], pointer:)
    else
      raise OmniSerializer::JsonapiError.new(
        detail: 'Malformed root data, should be an object with string `id` (optional), `type` and other members.',
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_collection_data!(key, value, pointer:)
    case value
    in { data: Array => data }
      data
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship, should be an array of objects with string `id` and `type`.",
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_collection_datum!(key, datum, association_types, pointer:)
    case datum
    in { id: String, type: String, **nil }
      validate_type!(datum, association_types.keys, pointer:)
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship datum, should be an object with string `id` and `type`.",
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_singular_data!(key, association_types, value, pointer:)
    case value
    in { data: { id: String, type: String, **nil } | nil => data }
      validate_type!(data, association_types.keys, pointer:) if data
      data
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship, should be an object with string `id` and `type` or null.",
        status: 400,
        source: { pointer: }
      )
    end
  end
end
