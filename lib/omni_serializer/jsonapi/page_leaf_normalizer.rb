# frozen_string_literal: true

# Normalizes leafs in `page` parameter family.
class OmniSerializer::Jsonapi::PageLeafNormalizer
  extend Dry::Initializer

  option :allowed_keys, OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol)
  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)

  def call(_, value, path:)
    raise invalid_page_error(value, path) unless value.is_a?(Hash)

    transformed_value = value.transform_keys { |key| missing_key_formatter.call(key) }

    raise invalid_page_keys_error(value, path) unless (transformed_value.keys.map(&:to_sym) - allowed_keys).empty?

    transformed_value
  end

  private

  def invalid_page_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid page parameter at `/#{path.join('/')}`, must be " \
        "a mapping with keys: #{allowed_keys.map { |key| "`#{key}`" }.join(', ')}, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: 'page' }
    )
  end

  def invalid_page_keys_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid page key at `/#{path.join('/')}`, allowed keys " \
        "are: #{allowed_keys.map { |key| "`#{key}`" }.join(', ')}, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: 'page' }
    )
  end
end
