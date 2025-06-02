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

  def call(resource_class, data:, included: [], **)
    type = type_formatter.call(resource_class.type)
    validate_root_data!(data, type)

    included = included_index(included)
    params, pointers = deserialize_resource(resource_class, pointer: '/data', included:, **data)
    pointers = { **ROOT_POINTERS, **pointers }
    params[:id] = data[:id] if data.key?(:id)

    Result.new(params:, pointers:)
  end

  private

  def included_index(included)
    included = included.map.with_index do |datum, index|
      pointer = "/included/#{index}"
      validate_resource_keys!(datum, pointer:)
      { **datum, pointer: }
    end
    included.index_by { |datum| datum.slice(:id, :lid, :type) }
  end

  def deserialize_resource(resource_class, pointer:, included:, attributes: {}, relationships: {}, **)
    type = type_formatter.call(resource_class.type)
    members, associations = format_members(resource_class)
    attributes, attribute_pointers = deserialize_attributes(type, members, associations, attributes, pointer:)
    relationships, relationship_pointers = deserialize_relationships(type, associations, relationships, included:,
      pointer:)

    params = { **attributes, **relationships }
    pointers = { **attribute_pointers, **relationship_pointers }

    [params, pointers]
  end

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

  def deserialize_attributes(type, members, associations, attributes, pointer:)
    pointer = "#{pointer}/attributes"
    mapping = attributes.transform_keys do |key|
      if associations[key.to_s]
        raise OmniSerializer::JsonapiError.new(
          detail: "Relationship `#{key}` on `#{type}` given as an attribute, please move it under `relationships`.",
          status: 400,
          source: { pointer: "#{pointer}/#{key}" }
        )
      end

      member = members[key]

      [member&.name || missing_key_formatter.call(key).to_sym, "#{pointer}/#{key}"]
    end

    [mapping.transform_keys(&:first), mapping.keys.to_h.transform_keys { |key| [key] }]
  end

  def deserialize_relationships(type, associations, relationships, included:, pointer:)
    pointer = "#{pointer}/relationships"
    mapping = relationships.map do |key, value|
      association = associations[key.to_s]

      unless association
        raise OmniSerializer::JsonapiError.new(
          detail: "Relationship `#{key}` is not defined on `#{type}`, " \
            "valid relationships are: `#{associations.keys.join('`, `')}`.",
          status: 400,
          source: { pointer: "#{pointer}/#{key}" }
        )
      end

      relationship_params(association, key, value, included:, pointer: "#{pointer}/#{key}")
    end

    mapping.each_with_object([{}, {}]) do |(attributes, pointers), (result_attributes, result_pointers)|
      result_attributes.merge!(attributes)
      result_pointers.merge!(pointers)
    end
  end

  def relationship_params(association, key, value, included:, pointer:)
    association_types = resolve_association_types(association)
    pointer = "#{pointer}/data"

    if association.collection
      data = validate_collection_data!(key, value, pointer:)
      collection_relationship_params(association, association_types, key, data, included:, pointer:)
    else
      data = validate_singular_data!(key, association_types, value, pointer:)
      singular_relationship_params(association, association_types, data, included:, pointer:)
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
      association_types.transform_values { |resource_class| [resource_class, entity_map[resource_class].name] }
    else
      association_types.transform_values { |resource_class| [resource_class, nil] }
    end
  end

  def collection_relationship_params(association, association_types, key, data, included:, pointer:)
    data.each.with_index do |datum, index|
      validate_collection_datum!(key, datum, association_types, pointer: "#{pointer}/#{index}")
    end

    linked_data_exists = data.any? { |datum| datum.key?(:lid) || included.key?(datum.slice(:id, :lid, :type)) }
    if linked_data_exists || association.polymorphic?
      deep_collection_relationship_params(association, association_types, data, included:, pointer:)
    else
      flat_collection_relationship_params(association, data, pointer:)
    end
  end

  def deep_collection_relationship_params(association, association_types, data, included:, pointer:)
    mapping = data.map.with_index do |datum, index|
      deep_collection_relationship_datum_params(association, association_types, datum, index, included:, pointer:)
    end

    params = mapping.map(&:first)
    pointers = mapping.map(&:second).inject({}, :merge)
    pointers[[]] = pointer

    [{ association.name => params }, pointers.transform_keys { |key| [association.name, *key] }]
  end

  def deep_collection_relationship_datum_params(association, association_types, datum, index, included:, pointer:)
    linked_data = included[datum.slice(:id, :lid, :type)]
    if linked_data
      params, pointers = included_relationship_params(
        association,
        *association_types.fetch(linked_data[:type]),
        linked_data,
        included:
      )
      [params, pointers.transform_keys { |key| [index, *key] }]
    elsif datum.key?(:lid)
      missing_lid_resource!(datum, "#{pointer}/#{index}")
    else
      deep_collection_relationship_simple_datum_params(association, association_types, datum, index, pointer:)
    end
  end

  def deep_collection_relationship_simple_datum_params(association, association_types, datum, index, pointer:)
    params = {}
    pointers = { [index] => "#{pointer}/#{index}" }
    if datum.key?(:id)
      params[:id] = datum[:id]
      pointers[[index, :id]] = "#{pointer}/#{index}/id"
    end
    if association.polymorphic?
      params[:type] = association_types.fetch(datum[:type]).second
      pointers[[index, :type]] = "#{pointer}/#{index}/type"
    end

    [params, pointers]
  end

  def flat_collection_relationship_params(association, data, pointer:)
    id_key = :"#{missing_key_formatter.call(association.name, :singular)}_ids"

    [
      { id_key => data.map { |datum| datum[:id] } },
      {
        [id_key] => pointer,
        **data.size.times.to_h { |index| [[id_key, index], "#{pointer}/#{index}/id"] }
      }
    ]
  end

  def singular_relationship_params(association, association_types, data, included:, pointer:)
    id_key = :"#{association.name}_id"

    if data.nil?
      [{ id_key => nil }, { [id_key] => pointer }]
    elsif included.key?(data.slice(:id, :lid, :type))
      linked_data = included[data.slice(:id, :lid, :type)]
      params, pointers = included_relationship_params(
        association,
        *association_types.fetch(linked_data[:type]),
        linked_data,
        included:
      )
      [{ association.name => params }, pointers.transform_keys { |key| [association.name, *key] }]
    elsif data.key?(:lid)
      missing_lid_resource!(data, pointer)
    else
      singular_relationship_simple_params(association, association_types, data, id_key, pointer:)
    end
  end

  def singular_relationship_simple_params(association, association_types, data, id_key, pointer:)
    type_key = :"#{association.name}_type"

    if association.polymorphic?
      [
        {
          id_key => data[:id],
          type_key => association_types.fetch(data[:type]).second
        },
        { [id_key] => "#{pointer}/id", [type_key] => "#{pointer}/type" }
      ]
    else
      [{ id_key => data[:id] }, { [id_key] => "#{pointer}/id" }]
    end
  end

  def included_relationship_params(association, resource_class, model_name, linked_data, included:)
    params, pointers = deserialize_resource(resource_class, included:, **linked_data)
    if linked_data.key?(:id)
      params[:id] = linked_data[:id]
      pointers[:id] = "#{linked_data[:pointer]}/id"
    end
    if association.polymorphic?
      params[:type] = model_name
      pointers[:type] = "#{linked_data[:pointer]}/type"
    end
    pointers[[]] = linked_data[:pointer]
    [params, pointers]
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
        detail: 'Malformed resource data, should be an object with string `id` (optional), `type` and other members.',
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_resource_keys!(data, pointer:)
    return if data.is_a?(Hash) &&
      (data.key?(:id) ? (data in { id: String, type: String }) : (data in { lid: String, type: String }))

    raise OmniSerializer::JsonapiError.new(
      detail: 'Malformed resource data, should be an object with string `id` (or `lid`), `type` and other members.',
      status: 400,
      source: { pointer: }
    )
  end

  def validate_collection_data!(key, value, pointer:)
    case value
    in { data: Array => data }
      data
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship, should be an " \
          'array of objects with string `id` (or `lid`) and `type`.',
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_collection_datum!(key, datum, association_types, pointer:)
    case datum
    in { id: String, type: String, **nil } | { lid: String, type: String, **nil }
      validate_type!(datum, association_types.keys, pointer:)
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship datum, should be an " \
          'object with string `id` (or `lid`) and `type`.',
        status: 400,
        source: { pointer: }
      )
    end
  end

  def validate_singular_data!(key, association_types, value, pointer:)
    case value
    in { data: { id: String, type: String, **nil } | { lid: String, type: String, **nil } | nil => data }
      validate_type!(data, association_types.keys, pointer:) if data
      data
    else
      raise OmniSerializer::JsonapiError.new(
        detail: "Malformed data for `#{key}` relationship, should be an " \
          'object with string `id` (or `lid`) and `type` or null.',
        status: 400,
        source: { pointer: }
      )
    end
  end

  def missing_lid_resource!(data, pointer)
    raise OmniSerializer::JsonapiError.new(
      detail: "Linked resource data for lid `#{data[:lid]}` not found in `included`.",
      status: 400,
      source: { pointer: }
    )
  end
end
