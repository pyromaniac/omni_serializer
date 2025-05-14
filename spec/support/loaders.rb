# frozen_string_literal: true

class BaseLoader
  extend Dry::Initializer

  param :scope, OmniSerializer::Types::Interface(:klass, :values, :where)
  param :path, OmniSerializer::Types::Coercible::Array.of(OmniSerializer::Types::Symbol).constrained(min_size: 1)

  def self.cache_key(scope, *, **)
    [scope.klass, scope.values, *, **]
  end

  def call(keys)
    raise NotImplementedError
  end

  private

  def basic_scope
    @basic_scope ||= if path.many?
      s = scope
      s = s.select(s.klass.arel_table[Arel.star]) if s.select_values.empty?
      s.select("#{path.join('.')} as #{path.join('_')}")
    else
      scope
    end
  end

  def keys_scope(keys)
    basic_scope.where(path.reverse.inject(keys) { |value, key| { key => value } })
  end
end

class RecordLoader < BaseLoader
  param :path, OmniSerializer::Types::Coercible::Array.of(OmniSerializer::Types::Symbol).constrained(min_size: 1),
    default: proc { [:id] }

  def call(keys)
    keys_scope(keys)
      .index_by(&path.join('_').to_sym)
      .reverse_merge(keys.zip([nil]).to_h)
  end
end

class CollectionLoader < BaseLoader
  def call(keys)
    keys_scope(keys)
      .group_by(&path.join('_').to_sym)
      .reverse_merge(keys.zip([[]] * keys.size).to_h)
  end
end

class AggregateLoader < BaseLoader
  param :aggregate, OmniSerializer::Types::Symbol.enum(:count, :sum, :average, :minimum, :maximum)
  option :aggregate_column, OmniSerializer::Types::Symbol, default: proc { :all }
  option :empty_value, default: proc { 0 }

  def call(keys)
    keys_scope(keys)
      .group(path.join('_'))
      .calculate(aggregate, aggregate_column)
      .reverse_merge(keys.zip([empty_value] * keys.size).to_h)
  end
end
