# frozen_string_literal: true

# Builds a query tree for the JSONAPI serializer arguments.
class OmniSerializer::Jsonapi::QueryBuilder
  extend Dry::Initializer

  DEFAULT_ATTRIBUTES = %i[id].freeze

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call), default: proc { ->(name) { name.split(':', 2) } }
  option :includes_normalizer, OmniSerializer::Types::Interface(:call),
    default: proc { OmniSerializer::Jsonapi::IncludeNormalizer.new(key_formatter:, type_formatter:, type_extractor:) }
  option :fields_normalizer, OmniSerializer::Types::Interface(:call),
    default: proc { OmniSerializer::Jsonapi::FieldsNormalizer.new(key_formatter:, type_formatter:) }
  option :filter_normalizer, OmniSerializer::Types::Interface(:call),
    default: proc { OmniSerializer::Jsonapi::FilterNormalizer.new(key_formatter:, type_formatter:, type_extractor:) }

  def call(resource_class, include: [], fields: {}, filter: {}, sort: [], **)
    includes_tree = includes_normalizer.call(resource_class, include)
    includes_map = build_includes_map(resource_class, includes_tree)
    fields = fields_normalizer.call(fields, included_resources: includes_map.keys)
    filter_tree = filter_normalizer.call(resource_class, filter)
    # sort_tree = normalize_sort(sort || [], resource_class, includes_map)

    arguments = filter_tree.key?([]) ? { filter: filter_tree[[]] } : {}
    OmniSerializer::Query.new(name: :root, arguments:, schema: {
      resource: resource_class,
      members: query_level(resource_class, includes_tree:, includes_map:, fields:, filter_tree:)
    })
  end

  private

  def build_includes_map(resource_class, includes_tree)
    initial_value = { resource_class => [] }
    includes_tree.each_with_object(initial_value) do |((name, association_resource), nested_includes), result|
      result[resource_class] |= [resource_class.members[name]]
      result.merge!(build_includes_map(association_resource, nested_includes)) { |_, one, two| one | two }
    end
  end

  def query_level(resource_class, includes_tree:, path: [], **query_options)
    includes_tree ||= {} if resource_class.collection?

    query_members(resource_class, path:, includes_tree:, **query_options) +
      query_associations(resource_class, path:, includes_tree:, **query_options)
  end

  def query_members(resource_class, fields:, **)
    members = if fields.key?(resource_class)
      fields[resource_class]
    else
      resource_class.members.values.grep(OmniSerializer::Resource::Member).select(&:expose)
    end
    members = resource_class.members.values_at(*DEFAULT_ATTRIBUTES).compact | members

    members.map do |member|
      OmniSerializer::Query.new(name: member.name, arguments: {}, schema: nil)
    end
  end

  def query_associations(resource_class, includes_tree:, includes_map:, filter_tree:, path:, **query_options)
    return [] if includes_tree.nil?

    includes_map[resource_class].map do |association|
      current_path = resource_class.collection? ? path : [*path, [resource_class, association.name]]
      filter_given = filter_tree.key?(current_path) && !resource_class.collection?
      arguments = filter_given ? { filter: filter_tree[current_path] } : {}
      OmniSerializer::Query.new(name: association.name, arguments:,
        schema: association_schema(association, includes_tree:,
          includes_map:, filter_tree:, path: current_path, **query_options))
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

  # def normalize_sort(sort, root_resource, _query_resources)
  #   sort = sort.split(',') if sort.is_a?(String)

  #   (sort || []).each_with_object({}) do |path, result|
  #     path = path.split('.') if path.is_a?(String)
  #     direction = path.any? { |segment| segment.start_with?('-') } ? :desc : :asc
  #     path = path.map { |segment| segment.delete_prefix('-') }

  #     resource = root_resource
  #     resource_chain = []
  #     path.each.with_index do |segment, index|
  #       member = resource_members(resource)[key_formatter.call(segment)]
  #       if member.is_a?(OmniSerializer::Resource::Association)
  #         resource = member.resolved_resource
  #         resource_chain.push(member.name)
  #       else
  #         (result[resource_chain] ||= {})[path[index..].join('.')] = direction
  #         break
  #       end
  #     end
  #   end
  # end
end
