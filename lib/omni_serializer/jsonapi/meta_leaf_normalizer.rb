# frozen_string_literal: true

# Normalizes leafs in `meta` parameter family.
class OmniSerializer::Jsonapi::MetaLeafNormalizer
  extend Dry::Initializer

  param :param_key, OmniSerializer::Types::Coercible::String
  option :key_formatter, OmniSerializer::Types::Interface(:call)

  def call(parent, value, path:)
    value = normalize_value(parent, value, path)
    transformed_meta = transformed_meta(parent)

    value.each_with_object({ extra: [], except: [] }) do |name, result|
      except, name = normalize_member(name, path, transformed_meta)
      except ? result[:except].push(name) : result[:extra].push(name)
    end
  end

  private

  def normalize_value(parent, value, path)
    value = value.split(',') if value.is_a?(String)

    raise invalid_meta_error(value, path) unless parent.is_a?(Class) && value.is_a?(Array)
    raise invalid_meta_target_error(path) unless parent.collection?

    value
  end

  def transformed_meta(resource_class)
    resource_class.members.values.grep(OmniSerializer::Resource::Member)
      .select { |member| member.macro == :meta }
      .index_by { |member| key_formatter.call(member.name) }
  end

  def normalize_member(name, path, transformed_meta)
    except = name.start_with?('-')
    name = name.delete_prefix('-')
    member = transformed_meta[name]

    raise invalid_meta_member_error(name, path, transformed_meta) unless member

    [except, member]
  end

  def invalid_meta_error(value, path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} parameter at `/#{path.join('/')}`, must be " \
        "a comma-separated list of fields, given: `#{value.to_json}`",
      status: 400,
      source: { parameter: param_key }
    )
  end

  def invalid_meta_target_error(path)
    OmniSerializer::JsonapiError.new(
      detail: "Invalid #{param_key} parameter at `/#{path.join('/')}`, must be applied to a collection resource",
      status: 400,
      source: { parameter: param_key }
    )
  end

  def invalid_meta_member_error(name, path, transformed_meta)
    OmniSerializer::JsonapiError.new(
      detail: "Undefined #{param_key} `#{name}` at `/#{path.join('/')}`, valid #{param_key} " \
        "fields are: `#{transformed_meta.keys.join('`, `')}`",
      status: 400,
      source: { parameter: param_key }
    )
  end
end
