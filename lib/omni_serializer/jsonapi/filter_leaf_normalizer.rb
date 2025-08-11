# frozen_string_literal: true

# Normalizes leafs in `filter` parameter family.
class OmniSerializer::Jsonapi::FilterLeafNormalizer
  extend Dry::Initializer

  option :missing_key_formatter, OmniSerializer::Types::Interface(:call)

  def call(parent, value, path:)
    raise invalid_filter_error(value, path) if parent.is_a?(Class) && !value.is_a?(Hash)

    OmniSerializer::Utils.deep_transform_keys(build_params_tree(value)) do |key|
      missing_key_formatter.call(key)
    end
  end

  private

  # Turns hashes like { 'foo.bar' => { 'moo.baz' => 42 } }
  # or { 'foo.bar.moo' => { 'baz' => 42 } }
  # or { 'foo.bar.moo.baz' => 42 }
  # or { 'foo' => { 'bar.moo.baz' => 42 } }
  # or { 'foo.bar' => { 'moo' { 'baz' => 42 } } }
  # into { 'foo' => { 'bar' => { 'moo' => { 'baz' => 42 } } } }
  def build_params_tree(params)
    return params unless params.is_a?(Hash)

    chains = params.map do |path, value|
      path = path.to_s.split('.') if path.is_a?(String) || path.is_a?(Symbol)
      value = OmniSerializer::Utils.deep_transform_keys(build_params_tree(value), &:to_s)
      path.reverse.inject(value) { |result, name| { name => result } }
    end

    chains.inject({}) { |result, chain| OmniSerializer::Utils.deep_merge(result, chain) }
  end

  def invalid_filter_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid filter parameter at `/#{path.join('/')}`, must be a mapping, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: 'filter' }
    )
  end
end
