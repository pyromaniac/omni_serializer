# frozen_string_literal: true

# Builds a query tree for the Simple serializer arguments.
class OmniSerializer::Simple::QueryBuilder
  extend Dry::Initializer

  RESERVED_QUERY_OPTION_KEYS = %i[only except extra include collection types].freeze

  # @param resource_class [Class] The resource class to serialize.
  # @param include [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param only [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param except [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param extra [Symbol | Array<Symbol>]
  # Any leftover keys are passed to the resource as query arguments.
  # @return [OmniSerializer::Query]
  def call(resource_class, **params)
    params = normalize_params(params)
    arguments, query_options = extract_arguments_and_query_options(params)

    OmniSerializer::Query.new(name: :root, arguments:, schema: {
      resource: resource_class,
      members: query_level(resource_class, **query_options)
    })
  end

  private

  def query_level(resource_class, **member_options)
    if resource_class.collection?
      query_collection(resource_class, **member_options)
    else
      query_members_and_associations(resource_class, **member_options)
    end
  end

  def query_members_and_associations(resource_class, include: nil, **member_options)
    query_members(resource_class, **member_options) + query_associations(resource_class, include:)
  end

  def query_collection(resource_class, collection: {}, **query_options)
    collection_member = resource_class.collection_member

    [OmniSerializer::Query.new(
      name: collection_member.name,
      arguments: {},
      schema: association_schema(collection_member, types: {}, **query_options)
    )] + query_members_and_associations(resource_class, **collection)
  end

  def query_members(resource_class, only: nil, except: [], extra: [], **)
    only ||= default_members(resource_class)
    member_params = normalize_nested_params(only)
      .merge(normalize_nested_params(extra))
      .except(*Array(except).map(&:to_sym))
    resource_class.members.slice(*member_params.keys).filter_map do |name, member|
      next unless member.is_a?(OmniSerializer::Resource::Member)

      OmniSerializer::Query.new(name:, arguments: member_params[name], schema: nil)
    end
  end

  def query_associations(resource_class, include:)
    normalize_nested_params(include).filter_map do |name, query_options|
      association = resource_class.members[name]

      next unless association.is_a?(OmniSerializer::Resource::Association)

      arguments, association_query_options = extract_arguments_and_query_options(query_options)

      OmniSerializer::Query.new(name:, arguments:, schema: association_schema(association, **association_query_options))
    end
  end

  def association_schema(association, types: {}, **query_options)
    if association.polymorphic?
      normalized_types = normalize_types(association, types)

      association.resolved_resource.transform_values do |resource_class|
        {
          resource: resource_class,
          members: query_level(resource_class, **(normalized_types[resource_class] || query_options))
        }
      end
    else
      {
        resource: association.resolved_resource,
        members: query_level(association.resolved_resource, **query_options)
      }
    end
  end

  def default_members(resource_class)
    resource_class.members.filter_map do |name, member|
      name if member in OmniSerializer::Resource::Member(expose: true)
    end
  end

  def normalize_params(params)
    OmniSerializer::Utils.deep_transform_keys(params) do |key|
      case key
      when String, Symbol
        key.to_sym
      else
        key
      end
    end
  end

  def normalize_types(association, types)
    association.resource_classes.each_with_object({}) do |resource_class, result|
      query_options = types[resource_class]
      query_options ||= types[resource_class.type.to_sym] if resource_class.type
      result[resource_class] = query_options if query_options
    end
  end

  def extract_arguments_and_query_options(query_options)
    [
      query_options.except(*RESERVED_QUERY_OPTION_KEYS),
      query_options.slice(*RESERVED_QUERY_OPTION_KEYS)
    ]
  end

  def normalize_nested_params(members)
    wrap_array(members).map do |member|
      case member
      in String | Symbol
        { member.to_sym => {} }
      in Hash
        member
      end
    end.inject({}, :merge)
  end

  def wrap_array(object)
    if object.nil?
      []
    elsif object.respond_to?(:to_ary)
      object.to_ary || [object]
    else
      [object]
    end
  end
end
