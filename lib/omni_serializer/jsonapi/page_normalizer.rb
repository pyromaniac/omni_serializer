# frozen_string_literal: true

# Normalizes the page parameter for the JSONAPI serializer.
class OmniSerializer::Jsonapi::PageNormalizer
  extend Dry::Initializer

  RelationshipParams = Struct.new(:raw_name, :name, :type, :value, keyword_init: true)

  param :param_key, OmniSerializer::Types::Coercible::String
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call)
  option :allowed_keys, OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol)
  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)

  def call(resource_class, page)
    Array.wrap(page.presence)
      .map { |params| normalize_params_tree(resource_class, params, display_path: [], query_path: []) }
      .inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  private

  def normalize_params_tree(resource_class, nested_params, display_path:, query_path:)
    return leaf_params_tree(query_path, nested_params, display_path:) unless nested_params.is_a?(Hash)

    resource_class = resource_class.collection_member.resolved_resource if resource_class.collection?
    transformed_associations = transformed_associations(resource_class)

    leaf_params, relationship_params = partition_params(nested_params, transformed_associations, display_path:)
    result = leaf_map(query_path, leaf_params, display_path:)

    relationship_params.reduce(result) do |current, relationship_params|
      child = normalize_relationship(resource_class, transformed_associations, relationship_params,
        display_path:, query_path:)
      OmniSerializer::Utils.deep_merge(current, child)
    end
  end

  def transformed_associations(resource_class)
    resource_class.members.values
      .grep(OmniSerializer::Resource::Association)
      .index_by { |member| key_formatter.call(member.name) }
  end

  def leaf_params_tree(query_path, value, display_path:)
    { query_path => normalize_leaf_value(value, display_path) }
  end

  def partition_params(nested_params, transformed_associations, display_path:)
    leaf_params = {}
    relationship_params = []

    nested_params.stringify_keys.each do |raw_name, value|
      name, type = type_extractor.call(raw_name)

      if value.is_a?(Hash)
        relationship_params << RelationshipParams.new(raw_name:, name:, type:, value:)
      elsif !allowed_leaf_key?(name) && transformed_associations.key?(name)
        normalize_leaf_value(value, [*display_path, raw_name])
      else
        leaf_params[name] = value
      end
    end

    [leaf_params, relationship_params]
  end

  def leaf_map(query_path, leaf_params, display_path:)
    return {} if leaf_params.empty?

    { query_path => normalize_leaf_value(leaf_params, display_path) }
  end

  def allowed_leaf_key?(name)
    allowed_keys.include?(missing_key_formatter.call(name))
  end

  def normalize_relationship(resource_class, transformed_associations, relationship_params, display_path:, query_path:)
    association = association_for(relationship_params, transformed_associations, display_path:)
    raise type_suffix_not_supported_error(relationship_params, display_path) if relationship_params.type

    association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }

    association_types.reduce({}) do |current, (_resource_type, association_resource)|
      child = normalize_relationship_tree(resource_class, association, association_resource, relationship_params,
        display_path:, query_path:)
      OmniSerializer::Utils.deep_merge(current, child)
    end
  end

  def association_for(relationship_params, transformed_associations, display_path:)
    association = transformed_associations[relationship_params.name]
    return association if association

    raise invalid_relationship_error(
      relationship_params.raw_name,
      [*display_path, relationship_params.raw_name],
      transformed_associations
    )
  end

  def normalize_relationship_tree(
    resource_class, association, association_resource, relationship_params, display_path:, query_path:
  )
    next_query_path = [*query_path, [resource_class, association.name]]
    next_display_path = [*display_path, relationship_params.raw_name]

    normalize_params_tree(
      association_resource,
      relationship_params.value,
      display_path: next_display_path,
      query_path: next_query_path
    )
  end

  def normalize_leaf_value(value, path)
    raise invalid_page_error(value, path) unless value.is_a?(Hash)

    transformed_value = value.transform_keys { |key| missing_key_formatter.call(key) }
    invalid_keys = transformed_value.keys.map(&:to_sym) - allowed_keys
    raise invalid_page_keys_error(value, invalid_keys, path) unless invalid_keys.empty?

    transformed_value
  end

  def invalid_page_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} parameter at `/#{path.join('/')}`, must be " \
        "a mapping with keys: `#{allowed_keys.join('`, `')}`, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: param_key }
    )
  end

  def invalid_page_keys_error(value, invalid_keys, path)
    invalid_value = value.stringify_keys.except(*allowed_keys.map(&:to_s)).slice(*invalid_keys.map(&:to_s))

    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} key at `/#{path.join('/')}`, allowed keys " \
        "are: `#{allowed_keys.join('`, `')}`, given: `#{invalid_value.to_json}`",
      status: 400,
      source: { parameter: param_key }
    )
  end

  def invalid_relationship_error(raw_name, display_path, transformed_associations)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} relationship `#{raw_name}` at `/#{display_path.join('/')}`, " \
        "valid relationships are: `#{transformed_associations.keys.join('`, `')}`",
      status: 400,
      source: { parameter: param_key }
    )
  end

  def type_suffix_not_supported_error(relationship_params, display_path)
    full_path = [*display_path, relationship_params.raw_name].join('/')
    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} relationship `#{relationship_params.raw_name}` at `/#{full_path}`, " \
        'type scoping is not supported for pagination',
      status: 400,
      source: { parameter: param_key }
    )
  end
end
