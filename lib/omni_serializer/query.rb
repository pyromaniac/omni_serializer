# frozen_string_literal: true

class OmniSerializer::Query < Dry::Struct
  include OmniSerializer::Inspect.new(:name, :arguments, :schema)

  class ResourceSchema < Dry::Struct
    include OmniSerializer::Inspect.new(:resource, :members)

    attribute :resource, OmniSerializer::Types::Resource
    attribute :members, OmniSerializer::Types::Array.of(OmniSerializer::Query)
  end

  attribute :name, OmniSerializer::Types::Symbol
  attribute :arguments, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)
  attribute :schema,
    (ResourceSchema | OmniSerializer::Types::Hash.map(OmniSerializer::Types::Class, ResourceSchema)).optional
end
