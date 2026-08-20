# frozen_string_literal: true

module OmniSerializer::Utils
  class << self
    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |_key, value1, value2|
        if value1.is_a?(Hash) && value2.is_a?(Hash)
          deep_merge(value1, value2)
        elsif value1.is_a?(Array) && value2.is_a?(Array)
          value1 + value2
        else
          value2
        end
      end
    end

    def deep_transform_keys(object, &)
      case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[yield(key)] = deep_transform_keys(value, &)
        end
      when Array
        object.map { |item| deep_transform_keys(item, &) }
      else
        object
      end
    end
  end
end
