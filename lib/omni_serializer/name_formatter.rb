# frozen_string_literal: true

class OmniSerializer::NameFormatter
  extend Dry::Initializer

  option :inflector, OmniSerializer::Types::Interface(:camelize, :dasherize, :underscore, :singularize, :pluralize)
  option :casing, OmniSerializer::Types::Symbol.enum(:camel, :kebab, :pascal, :snake).optional, default: proc {}
  option :number, OmniSerializer::Types::Symbol.enum(:singular, :plural).optional, default: proc {}

  def call(value, number = self.number)
    return if value.nil?

    transform_case(transform_number(value.to_s, number))
  end

  private

  def transform_number(value, number)
    case number
    when :singular
      inflector.singularize(value)
    when :plural
      inflector.pluralize(value)
    else
      value
    end
  end

  def transform_case(value)
    value = inflector.underscore(value).tr('/', '_') if casing

    case casing
    when :camel
      if inflector.respond_to?(:camelize_lower)
        inflector.camelize_lower(value) # Dry::Inflector
      else
        inflector.camelize(value, false) # ActiveSupport::Inflector
      end
    when :kebab
      inflector.dasherize(value)
    when :pascal
      inflector.camelize(value)
    else
      value
    end
  end
end
