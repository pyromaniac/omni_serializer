# frozen_string_literal: true

# Builds a query tree for the JSONAPI serializer arguments.
class OmniSerializer::Jsonapi::QueryBuilder
  extend Dry::Initializer

  DEFAULT_ATTRIBUTES = %i[id].freeze

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call), default: proc { ->(name) { name.split(':', 2) } }

  def call(resource_class, include: {}, fields: {}, filter: {}, sort: [], **)
    includes_tree = build_includes_tree(include)
    includes_tree = normalize_includes_tree(resource_class, includes_tree)
    includes_map = build_includes_map(resource_class, includes_tree)
    fields = normalize_fields(fields || {}, includes_map:)
    filter_tree = build_filter_tree(filter || {})
    filter_tree = normalize_filter_tree(resource_class, filter_tree, includes_map:)

    arguments = filter_tree.key?([]) ? { filter: filter_tree[[]] } : {}
    OmniSerializer::Query.new(name: :root, arguments:, schema: {
      resource: resource_class,
      members: query_level(resource_class, includes_tree:, includes_map:, fields:, filter_tree:)
    })
  end

  private

  def build_includes_tree(include)
    include = include.split(',') if include.is_a?(String)
    chains = (include || []).map do |path|
      path = path.split('.') if path.is_a?(String)
      path.reverse.inject({}) { |result, name| { name.to_s => result } }
    end
    chains.inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  def normalize_includes_tree(resource_class, includes_tree)
    if resource_class.collection?
      return {
        [resource_class.collection_member.name, resource_class.collection_member.resolved_resource] =>
          normalize_includes_tree(resource_class.collection_member.resolved_resource, includes_tree)
      }
    end

    transformed_associations = resource_class.members.values
      .grep(OmniSerializer::Resource::Association)
      .index_by { |member| key_formatter.call(member.name) }

    include_chains = includes_tree.flat_map do |name, nested_includes|
      name, type = type_extractor.call(name)
      association = transformed_associations[name]

      unless association
        raise OmniSerializer::JsonapiError.new(
          detail: "Invalid include `#{name}` for `#{type_formatter.call(resource_class.type)}`, " \
            "valid includes are: `#{transformed_associations.keys.join('`, `')}`",
          status: 400,
          source: { parameter: 'include' }
        )
      end

      association_types = association.resource_classes.index_by { |klass| type_formatter.call(klass.type) }

      if type
        unless association_types[type]
          raise OmniSerializer::JsonapiError.new(
            detail: "Invalid type `#{type}` for include `#{name}`, " \
              "valid types are: `#{association_types.keys.join('`, `')}`",
            status: 400,
            source: { parameter: 'include' }
          )
        end

        association_types.except(type).values.map do |klass|
          [[association.name, klass], {}]
        end + [[[association.name, association_types[type]],
          normalize_includes_tree(association_types[type], nested_includes)]]
      else
        association_types.values.map do |klass|
          [[association.name, klass], normalize_includes_tree(klass, nested_includes)]
        end
      end
    end
    include_chains.group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }
  end

  def build_includes_map(resource_class, includes_tree)
    initial_value = { resource_class => [] }
    includes_tree.each_with_object(initial_value) do |((name, association_resource), nested_includes), result|
      result[resource_class] |= [resource_class.members[name]]
      result.merge!(build_includes_map(association_resource, nested_includes)) { |_, one, two| one | two }
    end
  end

  def normalize_fields(fields, includes_map:)
    type_map = includes_map.keys.index_by { |resource_class| type_formatter.call(resource_class.type) }

    raise OmniSerializer::Error, '`fields` parameter must be an mapping' unless fields.is_a?(Hash)

    fields.to_h do |type, type_fields|
      type = type.to_s
      type_fields = type_fields.split(',') if type_fields.is_a?(String)
      resource_class = type_map[type]

      unless resource_class
        raise OmniSerializer::JsonapiError.new(
          detail: "Invalid type given: `#{type}`, valid types are: `#{type_map.keys.join('`, `')}`",
          status: 400,
          source: { parameter: 'fields' }
        )
      end

      members_map = resource_class.members.values.index_by { |member| key_formatter.call(member.name) }
      members = type_fields.filter_map do |field|
        member = members_map[field.to_s]

        unless member
          member_names = members_map.select { |_, m| m.is_a?(OmniSerializer::Resource::Member) }.keys
          raise OmniSerializer::JsonapiError.new(
            detail: "Undefined member `#{field}` for `#{type}`, valid members are: `#{member_names.join('`, `')}`",
            status: 400,
            source: { parameter: 'fields' }
          )
        end

        member if member.is_a?(OmniSerializer::Resource::Member)
      end

      [resource_class, members]
    end
  end

  def build_filter_tree(filter)
    raise OmniSerializer::Error, '`filter` parameter must be an mapping' unless filter.is_a?(Hash)

    chains = filter.map do |path, value|
      path = path.to_s.split('.') if path.is_a?(String) || path.is_a?(Symbol)
      value = OmniSerializer::Utils.deep_transform_keys(value, &:to_s)
      path.reverse.inject(value) { |result, name| { name.to_s => result } }
    end
    chains.inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  def normalize_filter_tree(resource_class, filter_tree, includes_map:)
    resource_class = resource_class.collection_member.resolved_resource if resource_class.collection?
    transformed_members = resource_class.members.values.index_by { |member| key_formatter.call(member.name) }

    filter_chains = filter_tree.flat_map do |name, nested_tree|
      name, type = type_extractor.call(name.to_s)
      member = transformed_members[name]

      case member
      when OmniSerializer::Resource::Association
        association_types = member.resource_classes.index_by { |klass| type_formatter.call(klass.type) }

        if type && !association_types[type]
          raise OmniSerializer::JsonapiError.new(
            detail: "Invalid type `#{type}` for filter on `#{name}`, " \
              "valid types are: `#{association_types.keys.join('`, `')}`",
            status: 400,
            source: { parameter: 'filter' }
          )
        end

        association_types.flat_map do |resource_type, association_resource|
          nested_tree = {} unless !type || type == resource_type
          nested_filter = normalize_filter_tree(association_resource, nested_tree, includes_map:)
          nested_filter.map do |nested_path, nested_value|
            [[[resource_class, member.name], *nested_path], nested_value]
          end
        end
      else
        [[[], { member&.name || name => nested_tree }]]
      end
    end
    filter_chains.group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }
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
