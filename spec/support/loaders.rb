# frozen_string_literal: true

require 'active_support/core_ext/hash/deep_transform_values'

class BaseLoader
  extend Dry::Initializer

  param :scope, OmniSerializer::Types::Interface(:where, :select)
  param :path, OmniSerializer::Types::Coercible::Array.of(OmniSerializer::Types::Symbol).constrained(min_size: 1)

  def self.scope?(value)
    value.respond_to?(:klass) && value.respond_to?(:values)
  end

  def self.cache_key(scope, *, **)
    if scope?(scope)
      [scope.klass, scope.values.deep_transform_values { |value| scope?(value) ? value.values : value }, *, **]
    else
      [scope, {}, *, **]
    end
  end

  def call(keys)
    raise NotImplementedError
  end

  private

  def keys_scope(keys)
    basic_scope.where(path.reverse.inject(keys) { |value, key| { key => value } })
  end

  def basic_scope
    @basic_scope ||= path.many? ? path_scope(path, scope) : scope
  end

  def path_scope(path, scope)
    scope = scope.select(scope.klass.arel_table[Arel.star]) if scope.select_values.empty?
    scope.select("#{path.join('.')} as #{path.join('_')}")
  end
end

class RecordLoader < BaseLoader
  param :path, OmniSerializer::Types::Coercible::Array.of(OmniSerializer::Types::Symbol).constrained(min_size: 1),
    default: proc { [:id] }

  def call(keys)
    keys_scope(keys)
      .index_by { |record| record.attributes.fetch(path.join('_')) }
      .reverse_merge(keys.zip([nil]).to_h)
  end
end

class CollectionLoader < BaseLoader
  def call(keys)
    keys_scope(keys)
      .group_by { |record| record.attributes.fetch(path.join('_')) }
      .reverse_merge(keys.zip([[]] * keys.size).to_h)
  end
end

class AggregateLoader < BaseLoader
  DEFAULT_EMPTY_VALUES = {
    count: 0,
    sum: 0,
    average: 0,
    minimum: nil,
    maximum: nil
  }.freeze

  param :aggregate, OmniSerializer::Types::Symbol.enum(:count, :sum, :average, :minimum, :maximum)
  option :aggregate_column, OmniSerializer::Types::Symbol, default: proc { :all }
  option :empty_value, default: proc { DEFAULT_EMPTY_VALUES[aggregate] }

  def call(keys)
    keys_scope(keys)
      .group(path.join('.'))
      .calculate(aggregate, aggregate_column)
      .reverse_merge(keys.zip([empty_value] * keys.size).to_h)
  end
end
