# frozen_string_literal: true

# Normalizes the include parameter for the JSONAPI serializer returning includes tree.
class OmniSerializer::Jsonapi::IncludeNormalizer
  extend Dry::Initializer

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call)

  def call(resource_class, include)
    paths = include || []
    paths = paths.split(',') if paths.is_a?(String)

    raise invalid_include_parameter_error(include) unless paths.is_a?(Array)

    includes_tree = build_includes_tree(paths, include)
    normalize_includes_tree(resource_class, includes_tree)
  end

  private

  def build_includes_tree(paths, include)
    chains = paths.map do |path|
      path = path.split('.') if path.is_a?(String)

      raise invalid_include_parameter_error(include) unless path.is_a?(Array) && path.all?(String)

      path.reverse.inject({}) { |result, name| { name.to_s => result } }
    end
    chains.inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  def normalize_includes_tree(resource_class, includes_tree)
    return normalize_collection_includes(resource_class, includes_tree) if resource_class.collection?

    transformed_associations = resource_class.members.values
      .grep(OmniSerializer::Resource::Association)
      .index_by { |member| key_formatter.call(member.name) }

    include_chains = includes_tree.flat_map do |name, nested_includes|
      include_chain(resource_class, name, nested_includes, transformed_associations)
    end

    include_chains.group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }
  end

  def normalize_collection_includes(resource_class, includes_tree)
    {
      [resource_class.collection_member.name, resource_class.collection_member.resolved_resource] =>
        normalize_includes_tree(resource_class.collection_member.resolved_resource, includes_tree)
    }
  end

  def include_chain(resource_class, name, nested_includes, transformed_associations)
    name, type = type_extractor.call(name)
    association = transformed_associations[name]

    raise invalid_include_error(name, resource_class, transformed_associations) unless association

    association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }

    association_includes(name, association_types, type, association, nested_includes)
  end

  def association_includes(name, association_types, type, association, nested_includes)
    if type
      raise invalid_type_error(type, name, association_types) unless association_types[type]

      specific_type_includes(association_types, type, association, nested_includes)
    else
      all_type_includes(association_types, association, nested_includes)
    end
  end

  def specific_type_includes(association_types, type, association, nested_includes)
    association_types.except(type).values.map do |klass|
      [[association.name, klass], {}]
    end + [[[association.name, association_types[type]],
      normalize_includes_tree(association_types[type], nested_includes)]]
  end

  def all_type_includes(association_types, association, nested_includes)
    association_types.values.map do |klass|
      [[association.name, klass], normalize_includes_tree(klass, nested_includes)]
    end
  end

  def invalid_include_parameter_error(include)
    OmniSerializer::JsonapiError.new(
      detail: "`include` parameter must be a string `include1.include2,include3`, given: `#{include.to_json}`",
      status: 400,
      source: { parameter: 'include' }
    )
  end

  def invalid_include_error(name, resource_class, transformed_associations)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid include `#{name}` for `#{type_formatter.call(resource_class.type)}`, " \
        "valid includes are: `#{transformed_associations.keys.join('`, `')}`",
      status: 400,
      source: { parameter: 'include' }
    )
  end

  def invalid_type_error(type, name, association_types)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid type `#{type}` for include `#{name}`, " \
        "valid types are: `#{association_types.keys.join('`, `')}`",
      status: 400,
      source: { parameter: 'include' }
    )
  end
end
