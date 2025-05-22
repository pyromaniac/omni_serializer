# frozen_string_literal: true

# Normalizes the fields parameter for the JSONAPI serializer.
class OmniSerializer::Jsonapi::FieldsNormalizer
  extend Dry::Initializer

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_formatter, OmniSerializer::Types::Interface(:call)

  def call(fields, included_resources:)
    fields ||= {}

    raise invalid_fields_parameter_error(fields) unless fields.is_a?(Hash)

    type_map = included_resources.index_by { |resource_class| type_formatter.call(resource_class.type) }
    normalize_fields(fields, type_map)
  end

  private

  def normalize_fields(fields, type_map)
    fields.to_h do |type, type_fields|
      type = type.to_s
      resource_class = type_map[type]

      raise invalid_type_error(type, type_map) unless resource_class

      type_fields = type_fields.split(',') if type_fields.is_a?(String)

      raise invalid_fields_parameter_error(fields) unless type_fields.is_a?(Array) && type_fields.all?(String)

      [resource_class, resource_members(resource_class, type_fields, type)]
    end
  end

  def resource_members(resource_class, type_fields, type)
    members_map = resource_class.members.values.index_by { |member| key_formatter.call(member.name) }
    type_fields.filter_map do |field|
      member = members_map.fetch(field.to_s) { raise invalid_field_error(type, field, members_map) }
      member if member.is_a?(OmniSerializer::Resource::Member)
    end
  end

  def invalid_fields_parameter_error(fields)
    OmniSerializer::JsonapiError.new(
      detail: "`fields` parameter must be a mapping `{\"type\":\"field1,field2\"}`, given: `#{fields.to_json}`",
      status: 400,
      source: { parameter: 'fields' }
    )
  end

  def invalid_type_error(type, type_map)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid type given: `#{type}`, valid types are: `#{type_map.keys.join('`, `')}`",
      status: 400,
      source: { parameter: 'fields' }
    )
  end

  def invalid_field_error(type, field, members_map)
    member_names = members_map.select { |_, m| m.is_a?(OmniSerializer::Resource::Member) }.keys

    OmniSerializer::JsonapiError.new(
      detail: "Undefined member `#{field}` for `#{type}`, valid members are: `#{member_names.join('`, `')}`",
      status: 400,
      source: { parameter: 'fields' }
    )
  end
end
