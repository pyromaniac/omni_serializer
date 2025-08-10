# frozen_string_literal: true

# Builds a query tree for the JSONAPI serializer arguments.
class OmniSerializer::Jsonapi::QueryBuilder
  extend Dry::Initializer

  DEFAULT_ATTRIBUTES = %i[id].freeze
  DEFAULT_TYPE_EXTRACTOR = ->(name) { name.split(':', 2) }
  META_KEY = :'omni:meta'

  option :include_normalizer, OmniSerializer::Types::Interface(:call)
  option :fields_normalizer, OmniSerializer::Types::Interface(:call)
  option :meta_normalizer, OmniSerializer::Types::Interface(:call)
  option :family_normalizers, OmniSerializer::Types::Array.of(OmniSerializer::Types::Interface(:call))

  def self.build(missing_key_formatter:, key_formatter:, type_formatter:, type_extractor: DEFAULT_TYPE_EXTRACTOR, **)
    new(
      include_normalizer: OmniSerializer::Jsonapi::IncludeNormalizer
        .new(key_formatter:, type_formatter:, type_extractor:),
      fields_normalizer: OmniSerializer::Jsonapi::FieldsNormalizer.new(key_formatter:, type_formatter:),
      meta_normalizer: OmniSerializer::Jsonapi::FamilyNormalizer.new(
        META_KEY, key_formatter:, type_formatter:, type_extractor:,
        leaf_normalizer: OmniSerializer::Jsonapi::MetaLeafNormalizer.new(META_KEY, key_formatter:)
      ),
      family_normalizers: [
        OmniSerializer::Jsonapi::FamilyNormalizer.new(
          'filter', key_formatter:, type_formatter:, type_extractor:,
          leaf_normalizer: OmniSerializer::Jsonapi::FilterLeafNormalizer.new(missing_key_formatter:)
        ),
        OmniSerializer::Jsonapi::FamilyNormalizer.new(
          'sort', key_formatter:, type_formatter:, type_extractor:,
          leaf_normalizer: OmniSerializer::Jsonapi::SortLeafNormalizer.new(missing_key_formatter:, key_formatter:)
        ),
        OmniSerializer::Jsonapi::FamilyNormalizer.new(
          'page', key_formatter:, type_formatter:, type_extractor:,
          leaf_normalizer: OmniSerializer::Jsonapi::PageLeafNormalizer.new(
            allowed_keys: %i[number size cursor before after],
            missing_key_formatter:
          )
        )
      ]
    )
  end

  def call(resource_class, relationship = nil, **)
    root_resource_class = resource_class
    resource_class, relationship = relationship_resource(resource_class, relationship) if relationship
    query_params = normalize_query_params(resource_class, **)

    if relationship
      OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
        resource: root_resource_class,
        members: [
          OmniSerializer::Query.new(
            name: relationship.name,
            arguments: path_arguments(query_params[:family_params], []),
            schema: {
              resource: resource_class,
              members: query_level(resource_class, **query_params)
            }
          )
        ]
      })
    else
      OmniSerializer::Query.new(name: :root, arguments: path_arguments(query_params[:family_params], []), schema: {
        resource: resource_class,
        members: query_level(resource_class, **query_params)
      })
    end
  end

  private

  def relationship_resource(resource_class, relationship)
    relationship = resource_class.members[relationship]
    [relationship.resolved_resource, relationship]
  end

  def normalize_query_params(resource_class, include: [], fields: {}, **params)
    includes_tree = include_normalizer.call(resource_class, include)
    includes_map = build_includes_map(resource_class, includes_tree)

    {
      includes_tree:,
      includes_map:,
      fields: fields_normalizer.call(fields, included_resources: includes_map.keys),
      meta: meta_normalizer.call(resource_class, params[meta_normalizer.param_key.to_sym]),
      family_params: normalize_family_params(resource_class, **params)
    }
  end

  def build_includes_map(resource_class, includes_tree)
    initial_value = { resource_class => [] }
    includes_tree.each_with_object(initial_value) do |((name, association_resource), nested_includes), result|
      result[resource_class] |= [resource_class.members[name]]
      result.merge!(build_includes_map(association_resource, nested_includes)) { |_, one, two| one | two }
    end
  end

  def normalize_family_params(resource_class, **params)
    family_normalizers.to_h do |normalizer|
      key = normalizer.param_key.to_sym
      [key, normalizer.call(resource_class, params[key])]
    end
  end

  def path_arguments(family_params, path)
    family_normalizers.filter_map do |normalizer|
      key = normalizer.param_key.to_sym
      [key, family_params[key][path]] if family_params[key].key?(path)
    end.to_h
  end

  def query_level(resource_class, includes_tree:, path: [], **query_options)
    includes_tree ||= {} if resource_class.collection?

    query_members(resource_class, path:, includes_tree:, **query_options) +
      (includes_tree.nil? ? [] : query_associations(resource_class, path:, includes_tree:, **query_options))
  end

  def query_members(resource_class, **)
    members = resource_fields(resource_class, **)
    members = resource_meta(members, **) if resource_class.collection?
    members.map do |member|
      OmniSerializer::Query.new(name: member.name, arguments: {}, schema: nil)
    end
  end

  def resource_fields(resource_class, fields:, **)
    members = if fields.key?(resource_class)
      fields[resource_class].grep(OmniSerializer::Resource::Member)
    else
      resource_class.members.values.grep(OmniSerializer::Resource::Member).select(&:expose)
    end
    resource_class.members.values_at(*DEFAULT_ATTRIBUTES).compact | members
  end

  def resource_meta(members, meta:, path:, **)
    if meta.key?(path)
      members -= meta[path][:except]
      members |= meta[path][:extra]
    end

    members
  end

  def query_associations(resource_class, includes_map:, family_params:, fields:, path:, **)
    associations = includes_map[resource_class]
    associations &= fields[resource_class] if fields.key?(resource_class)
    associations |= [resource_class.collection_member] if resource_class.collection?

    associations.map do |association|
      current_path = resource_class.collection? ? path : [*path, [resource_class, association.name]]
      arguments = resource_class.collection? ? {} : path_arguments(family_params, current_path)
      OmniSerializer::Query.new(name: association.name, arguments:,
        schema: association_schema(association, includes_map:, family_params:, fields:, path: current_path, **))
    end
  end

  def association_schema(association, includes_tree:, **query_options)
    if association.polymorphic?
      association.resolved_resource.transform_values do |resource_class|
        {
          resource: resource_class,
          members: query_level(resource_class,
            includes_tree: includes_tree[[association.name, resource_class]], **query_options)
        }
      end
    else
      {
        resource: association.resolved_resource,
        members: query_level(association.resolved_resource,
          includes_tree: includes_tree[[association.name, association.resolved_resource]], **query_options)
      }
    end
  end
end
