# frozen_string_literal: true

class OmniSerializer::Jsonapi::QueryBuilder
  extend Dry::Initializer

  DEFAULT_ATTRIBUTES = %i[id].freeze

  option :inflector, OmniSerializer::Types::Interface(:underscore, :dasherize, :camelize, :singularize, :pluralize)
  option :key_transform, OmniSerializer::Types::Transform, default: proc {}
  option :type_transform, OmniSerializer::Types::Transform, default: proc {}
  option :type_number, OmniSerializer::Types::Symbol.enum(:singular, :plural), default: proc { :plural }

  option :type_extractor, OmniSerializer::Types::Interface(:call), default: proc { ->(name) { name.split(':', 2) } }

  def call(resource_class, include: {}, fields: {}, filter: {}, sort: [], **_query_options)
    includes_tree = build_includes_tree(include)
    includes_tree = normalize_includes_tree(resource_class, includes_tree)
    includes_map = build_includes_map(resource_class, includes_tree)
    fields = normalize_fields(fields || {}, includes_map:)
    filter_tree = build_filter_tree(filter || {})
    filter_tree = normalize_filter_tree(resource_class, filter_tree, includes_map:)
    filter_tree = filter_tree.group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }

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
        [resource_class.collection_member.name, resource_class.collection_member.resource_class] =>
          normalize_includes_tree(resource_class.collection_member.resource_class, includes_tree)
      }
    end

    transformed_members = resource_class.members.values.index_by { |member| transform_key(member.name) }

    includes_tree.flat_map do |name, nested_includes|
      name, type = type_extractor.call(name)
      association = transformed_members[name]

      unless association.is_a?(OmniSerializer::Resource::Association)
        raise OmniSerializer::UndefinedAssociation.new(resource_class, name)
      end

      association_types = if association.resource_class.is_a?(Hash)
        association.resource_class.values.index_by { |resource_class| transform_type(resource_class.type) }
      else
        { transform_type(association.resource_class.type) => association.resource_class }
      end

      if type
        raise OmniSerializer::UndefinedAssociationType.new(resource_class, name, type) unless association_types[type]

        association_types.except(type).values.map do |resource_class|
          [[association.name, resource_class], {}]
        end + [[[association.name, association_types[type]],
          normalize_includes_tree(association_types[type], nested_includes)]]
      else
        association_types.values.map do |resource_class|
          [[association.name, resource_class], normalize_includes_tree(resource_class, nested_includes)]
        end
      end
    end.group_by(&:first).transform_values { |values| values.map(&:last).inject({}, :merge) }
  end

  def build_includes_map(resource_class, includes_tree)
    includes_tree.each_with_object({ resource_class => [] }) do |((name, association_resource), nested_includes), result|
      result[resource_class] |= [resource_class.members[name]]
      result.merge!(build_includes_map(association_resource, nested_includes)) { |_, one, two| one | two }
    end
  end

  def normalize_fields(fields, includes_map:)
    type_map = includes_map.keys.index_by { |resource_class| transform_type(resource_class.type) }

    raise OmniSerializer::Error, '`fields` parameter must be an mapping' unless fields.is_a?(Hash)

    fields.to_h do |type, fields|
      fields = fields.split(',') if fields.is_a?(String)
      resource_class = type_map[type.to_s]

      raise OmniSerializer::UndefinedQueryType.new(type, type_map.keys) unless resource_class

      members_map = resource_class.members.values.index_by { |member| transform_key(member.name) }
      members = fields.filter_map do |field|
        member = members_map[field.to_s]

        raise OmniSerializer::UndefinedMember.new(resource_class, field) unless member

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
    resource_class = resource_class.collection_member.resource_class if resource_class.collection?
    transformed_members = resource_class.members.values.index_by { |member| transform_key(member.name) }

    filter_tree.flat_map do |name, nested_tree|
      name, type = type_extractor.call(name.to_s)
      member = transformed_members[name]

      case member
      when OmniSerializer::Resource::Association
        association_types = if member.resource_class.is_a?(Hash)
          member.resource_class.values.index_by { |resource_class| transform_type(resource_class.type) }
        else
          { transform_type(member.resource_class.type) => member.resource_class }
        end

        if type && !association_types[type]
          raise OmniSerializer::UndefinedAssociationType.new(resource_class, name,
            type)
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
  end

  def query_level(resource_class, includes_tree:, path: [], **query_options)
    includes_tree ||= {} if resource_class.collection?

    query_members(resource_class, path:, includes_tree:, **query_options) +
      query_associations(resource_class, path:, includes_tree:, **query_options)
  end

  def query_members(resource_class, fields:, includes_tree:, **)
    members = if fields.key?(resource_class)
      fields[resource_class]
    else
      resource_class.members.values.grep(OmniSerializer::Resource::Member).select(&:expose)
    end
    members = resource_class.members.values_at(*DEFAULT_ATTRIBUTES).compact | members

    members.map do |members|
      OmniSerializer::Query.new(name: members.name, arguments: {}, schema: nil)
    end
  end

  def query_associations(resource_class, includes_tree:, includes_map:, filter_tree:, path:, **query_options)
    return [] if includes_tree.nil?

    includes_map[resource_class].map do |association|
      current_path = resource_class.collection? ? path : [*path, [resource_class, association.name]]
      arguments = filter_tree.key?(current_path) && !resource_class.collection? ? { filter: filter_tree[current_path] } : {}
      OmniSerializer::Query.new(name: association.name, arguments:,
        schema: association_schema(association, includes_tree:,
          includes_map:, filter_tree:, path: current_path, **query_options))
    end
  end

  def association_schema(association, includes_tree:, **query_options)
    if association.resource_class.is_a?(Hash)
      association.resource_class.transform_values do |resource_class|
        {
          resource: resource_class,
          members: query_level(resource_class,
            includes_tree: includes_tree[[association.name, resource_class]], **query_options)
        }
      end
    else
      {
        resource: association.resource_class,
        members: query_level(association.resource_class,
          includes_tree: includes_tree[[association.name, association.resource_class]], **query_options)
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
  #       member = resource_members(resource)[transform_key(segment)]
  #       if member.is_a?(OmniSerializer::Resource::Association)
  #         resource = member.resource_class
  #         resource_chain.push(member.name)
  #       else
  #         (result[resource_chain] ||= {})[path[index..].join('.')] = direction
  #         break
  #       end
  #     end
  #   end
  # end

  def transform_type(type)
    type = case type_number
    when :singular
      inflector.singularize(type)
    when :plural
      inflector.pluralize(type)
    end

    transform_key(type, type_transform)
  end

  def transform_key(key, transform = key_transform)
    case transform
    when :camel
      inflector.camelize(key)
    when :camel_lower
      inflector.respond_to?(:camelize_lower) ? inflector.camelize_lower(key) : inflector.camelize(key, false)
    when :dash
      inflector.dasherize(key)
    when :underscore
      inflector.underscore(key)
    else
      key.to_s
    end
  end
end
