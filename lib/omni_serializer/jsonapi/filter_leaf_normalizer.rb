# frozen_string_literal: true

# Normalizes leafs in `filter` parameter family.
class OmniSerializer::Jsonapi::FilterLeafNormalizer
  extend Dry::Initializer

  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)

  def call(parent, value, path:)
    raise invalid_relationship_family_error(value, path) if parent.is_a?(Class) && !value.is_a?(Hash)

    OmniSerializer::Utils.deep_transform_keys(value) { |key| missing_key_formatter.call(key) }
  end

  private

  def invalid_relationship_family_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid filter parameter at `/#{path.join('/')}`, must be a mapping, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: 'filter' }
    )
  end
end
