# frozen_string_literal: true

class OmniSerializer::Simple::QueryBuilder
  extend Dry::Initializer

  # @param resource_class [Class] The resource class to serialize.
  # @param params [Hash] The params to use for serialization.
  # @param include [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param only [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param except [Symbol | Array<Symbol | Hash<Symbol, Hash>> | Hash<Symbol, Hash>]
  # @param extra [Symbol | Array<Symbol>]
  # @return [OmniSerializer::Query]
  def call(resource_class, params: {}, **query_options)
    OmniSerializer::Query.new(name: :root, arguments: params, schema: {
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
      schema: {
        resource: collection_member.resource_class,
        members: query_level(collection_member.resource_class, **query_options)
      }
    )] + query_members_and_associations(resource_class, **collection)
  end

  def query_members(resource_class, only: nil, except: [], extra: [])
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

      OmniSerializer::Query.new(name:, arguments: query_options[:params] || {},
        schema: association_schema(association, **query_options.except(:params)))
    end
  end

  def association_schema(association, types: {}, **query_options)
    if association.resource_class.is_a?(Hash)
      association.resource_class.transform_values do |resource_class|
        {
          resource: resource_class,
          members: query_level(resource_class, **(types[resource_class] || query_options))
        }
      end
    else
      {
        resource: association.resource_class,
        members: query_level(association.resource_class, **query_options)
      }
    end
  end

  def default_members(resource_class)
    resource_class.members.filter_map do |name, member|
      name if member.is_a?(OmniSerializer::Resource::Member) && member.expose
    end
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
