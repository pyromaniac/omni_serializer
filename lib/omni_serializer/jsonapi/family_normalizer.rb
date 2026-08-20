# frozen_string_literal: true

# Normalizes a single parameter family for the JSONAPI serializer.
# This class mostly composes paths (relationships and members) and
# leaf values are processed by `leaf_normalizer`.
class OmniSerializer::Jsonapi::FamilyNormalizer
  extend Dry::Initializer

  RelationshipSegment = Struct.new(:resource_class, :association, :association_resource)

  param :param_key, OmniSerializer::Types::Coercible::String
  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call)
  option :leaf_normalizer, OmniSerializer::Types::Interface(:call)

  def call(resource_class, family)
    Array.wrap(family.presence)
      .map { |params| normalize_params_tree(resource_class, params) }
      .inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  private

  def normalize_params_tree(resource_class, nested_params, path: [])
    if nested_params.is_a?(Hash)
      param_trees(resource_class, nested_params.stringify_keys, path:).group_by(&:first).transform_values do |pairs|
        values = pairs.map(&:last)
        values.many? ? deep_merge_values(values) : values.first
      end
    else
      { [] => leaf_normalizer.call(resource_class, nested_params, path:) }
    end
  end

  def deep_merge_values(values)
    values.inject({}) { |result, value| OmniSerializer::Utils.deep_merge(result, value) }
  end

  def param_trees(resource_class, nested_params, path:)
    (nested_params || {}).flat_map do |(name, value)|
      collection_branches.call(member_resource_classes(resource_class), name).flat_map do |klass, members|
        params_chain(klass, name, value, members, path:)
      end
    end
  end

  # A collection serves several types, and each of them answers for itself.
  def member_resource_classes(resource_class)
    return [resource_class] unless resource_class.collection?

    resource_class.collection_member.resource_classes
  end

  def member_names(resource_class)
    resource_class.members.values.map { |member| key_formatter.call(member.name) }
  end

  def collection_branches
    @collection_branches ||= OmniSerializer::Jsonapi::CollectionBranches.new(
      key_formatter:, type_extractor:, relationship_resolver: method(:relationship_chain)
    )
  end

  def params_chain(resource_class, name, nested_params, transformed_members, path:)
    nested_relationship = dotted_relationship_chain(resource_class, name, nested_params, path:) if name.include?('.')
    return nested_relationship if nested_relationship

    path = [*path, name]
    name, type = type_extractor.call(name)
    member = transformed_members[name]

    if member.is_a?(OmniSerializer::Resource::Association)
      association_params(resource_class, member, name, type, nested_params, path:)
    elsif member
      [[[], { member&.name => leaf_normalizer.call(member, nested_params, path:) }]]
    else
      [[[], leaf_normalizer.call(nil, { name => nested_params }, path: path[..-2])]]
    end
  end

  def dotted_relationship_chain(resource_class, name, nested_params, path:)
    relationship_chains = relationship_chain(resource_class, name)
    return unless relationship_chains

    relationship_chains.flat_map do |relationship_chain|
      association_path = relationship_chain.map { |segment| [segment.resource_class, segment.association.name] }
      nested_result = normalize_params_tree(
        relationship_chain.last.association_resource,
        nested_params,
        path: [*path, name]
      )

      nested_result.map do |nested_path, value|
        [[*association_path, *nested_path], value]
      end
    end
  end

  def relationship_chain(resource_class, name)
    member_resource_classes(resource_class)
      .filter_map { |klass| resource_relationship_chain(klass, name) }.flatten(1).presence
  end

  def resource_relationship_chain(resource_class, name)
    relationship_name, nested_name = name.split('.', 2)

    association = association_for(resource_class, relationship_name)
    return unless association

    association_resources = association_resources(association, relationship_name)
    return terminal_relationship_chains(resource_class, association, association_resources) unless nested_name

    nested_chains = nested_relationship_chains(association_resources, nested_name)
    return unless nested_chains

    association_resources.flat_map do |association_resource|
      nested_resource_chains = nested_chains.fetch(association_resource)

      nested_resource_chains.map do |nested_chain|
        [RelationshipSegment.new(resource_class, association, association_resource), *nested_chain]
      end
    end
  end

  def association_for(resource_class, relationship_name)
    name, = type_extractor.call(relationship_name)
    member = resource_class.members.values.find { |candidate| key_formatter.call(candidate.name) == name }

    member if member.is_a?(OmniSerializer::Resource::Association)
  end

  def association_resources(association, relationship_name)
    association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }
    _name, type = type_extractor.call(relationship_name)
    raise invalid_type_error(association.name, type, association_types) if type && !association_types.key?(type)

    type ? [association_types.fetch(type)] : association_types.values
  end

  def terminal_relationship_chains(resource_class, association, association_resources)
    association_resources.map do |association_resource|
      [RelationshipSegment.new(resource_class, association, association_resource)]
    end
  end

  def nested_relationship_chains(association_resources, nested_name)
    nested_chains = association_resources.to_h do |association_resource|
      [association_resource, relationship_chain(association_resource, nested_name)]
    end

    nested_chains.value?(nil) ? nil : nested_chains
  end

  def association_params(resource_class, association, name, type, nested_params, **)
    association_types, recognized_names, consumed_names =
      association_param_context(association, name, type, nested_params)

    association_types.flat_map do |resource_type, association_resource|
      next [] if skipped_resource_type?(type, resource_type)

      params = association_nested_params(association_resource, nested_params, consumed_names, recognized_names)
      association_param_values(resource_class, association, association_resource, params, **)
    end
  end

  def association_param_context(association, name, type, nested_params)
    association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }

    raise invalid_type_error(name, type, association_types) if type && !association_types.key?(type)

    recognized_names = type ? {} : recognized_param_names(association_types.values, nested_params)
    consumed_names = recognized_names.values.reduce([], :|)

    [association_types, recognized_names, consumed_names]
  end

  def skipped_resource_type?(type, resource_type)
    type && type != resource_type
  end

  def association_param_values(resource_class, association, association_resource, params, **)
    normalize_params_tree(association_resource, params, **).map do |segment, value|
      [[[resource_class, association.name], *segment], value]
    end
  end

  def recognized_param_names(association_resources, nested_params)
    return {} unless nested_params.is_a?(Hash)

    names = nested_params.stringify_keys.keys

    association_resources.to_h do |association_resource|
      [association_resource, names.select { |name| recognized_param?(association_resource, name) }]
    end
  end

  def association_nested_params(association_resource, nested_params, consumed_names, recognized_names)
    return nested_params if consumed_names.blank? || !nested_params.is_a?(Hash)

    branch_names = recognized_names.fetch(association_resource, [])
    nested_params.stringify_keys.except(*(consumed_names - branch_names))
  end

  def recognized_param?(resource_class, name)
    return true if relationship_chain(resource_class, name)

    name, = type_extractor.call(name)

    member_resource_classes(resource_class).any? { |klass| member_names(klass).include?(name) }
  end

  def invalid_type_error(name, type, association_types)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid type `#{type}` for #{param_key} on `#{name}`, " \
        "valid types are: `#{association_types.keys.join('`, `')}`",
      status: 400,
      source: { parameter: param_key }
    )
  end
end
