# frozen_string_literal: true

# Normalizes the filter parameter for the JSONAPI serializer.
class OmniSerializer::Jsonapi::FilterNormalizer
  extend Dry::Initializer

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call)

  def call(resource_class, filter)
    filter ||= {}

    raise invalid_filter_error(filter) unless filter.is_a?(Hash)

    filter_tree = build_filter_tree(filter)
    normalize_filter_tree(resource_class, filter_tree)
  end

  private

  # Turns hashes like { 'foo.bar' => { 'moo.baz' => 42 } }
  # or { 'foo.bar.moo' => { 'baz' => 42 } }
  # or { 'foo.bar.moo.baz' => 42 }
  # or { 'foo' => { 'bar.moo.baz' => 42 } }
  # or { 'foo.bar' => { 'moo' { 'baz' => 42 } } }
  # into { 'foo' => { 'bar' => { 'moo' => { 'baz' => 42 } } } }
  def build_filter_tree(filter)
    return filter unless filter.is_a?(Hash)

    chains = filter.map do |path, value|
      path = path.to_s.split('.') if path.is_a?(String) || path.is_a?(Symbol)
      value = OmniSerializer::Utils.deep_transform_keys(build_filter_tree(value), &:to_s)
      path.reverse.inject(value) { |result, name| { name.to_s => result } }
    end

    chains.inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  def normalize_filter_tree(resource_class, filter_tree)
    resource_class = resource_class.collection_member.resolved_resource if resource_class.collection?
    transformed_members = resource_class.members.values.index_by { |member| key_formatter.call(member.name) }

    filter_chains(resource_class, filter_tree, transformed_members)
      .group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }
  end

  def filter_chains(resource_class, filter_tree, transformed_members)
    filter_tree.flat_map do |name, nested_tree|
      filter_chain(resource_class, name, nested_tree, transformed_members)
    end
  end

  def filter_chain(resource_class, name, nested_tree, transformed_members)
    name, type = type_extractor.call(name)
    member = transformed_members[name]

    case member
    when OmniSerializer::Resource::Association
      raise invalid_relationship_filter_error(name, nested_tree) unless nested_tree.is_a?(Hash)

      association_types = member.resource_classes.index_by { |klass| type_formatter.call(klass.type) }
      type_filter(resource_class, member, name, type, association_types, nested_tree)
    else
      [[[], { member&.name || name.to_sym => nested_tree }]]
    end
  end

  def type_filter(resource_class, member, name, type, association_types, nested_tree)
    raise invalid_type_error(name, type, association_types) if type && !association_types.key?(type)

    association_types.flat_map do |resource_type, association_resource|
      nested_filter = normalize_filter_tree(association_resource, type && type != resource_type ? {} : nested_tree)
      nested_filter.map do |nested_path, nested_value|
        [[[resource_class, member.name], *nested_path], nested_value]
      end
    end
  end

  def invalid_filter_error(filter)
    OmniSerializer::JsonapiError.new(
      detail: "`filter` parameter must be a mapping, given: `#{filter.to_json}`",
      status: 400,
      source: { parameter: 'filter' }
    )
  end

  def invalid_relationship_filter_error(name, nested_tree)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid filter on `#{name}` relationship, must be a mapping, given: `#{nested_tree.to_json}`",
      status: 400,
      source: { parameter: 'filter' }
    )
  end

  def invalid_type_error(name, type, association_types)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid type `#{type}` for filter on `#{name}`, " \
        "valid types are: `#{association_types.keys.join('`, `')}`",
      status: 400,
      source: { parameter: 'filter' }
    )
  end
end
