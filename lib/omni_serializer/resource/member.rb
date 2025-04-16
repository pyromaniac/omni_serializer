# frozen_string_literal: true

class OmniSerializer::Resource::Member < Dry::Struct
  attribute :name, OmniSerializer::Types::Symbol
  attribute :macro, OmniSerializer::Types::Symbol
  attribute :evaluator, OmniSerializer::Types::Interface(:call).optional
  attribute :condition, OmniSerializer::Types::Symbol | OmniSerializer::Types::Interface(:call).optional
  attribute :expose, OmniSerializer::Types::Bool
end
