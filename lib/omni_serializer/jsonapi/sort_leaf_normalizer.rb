# frozen_string_literal: true

# Normalizes leafs in `sort` parameter family.
class OmniSerializer::Jsonapi::SortLeafNormalizer
  extend Dry::Initializer

  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)
  option :key_formatter, OmniSerializer::Types::Interface(:call)

  def call(parent, value, path:)
    value = value.split(',') if value.is_a?(String)

    raise invalid_sort_error(value, path) unless parent.is_a?(Class) && value.is_a?(Array)

    transformed_members = parent.members.values.index_by { |member| key_formatter.call(member.name) }

    value.to_h { |name| normalize_member(name, transformed_members) }
  end

  private

  def normalize_member(name, transformed_members)
    direction = name.start_with?('-') ? :desc : :asc
    name = name.delete_prefix('-')
    member = transformed_members[name]

    [member&.name || missing_key_formatter.call(name), direction]
  end

  def invalid_sort_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid sort parameter at `/#{path.join('/')}`, must be " \
        "a comma-separated list of fields, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: 'sort' }
    )
  end
end
