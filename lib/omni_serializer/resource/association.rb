# frozen_string_literal: true

class OmniSerializer::Resource::Association < Dry::Struct
  attribute :name, OmniSerializer::Types::Symbol
  attribute :evaluator, OmniSerializer::Types::Interface(:call).optional
  attribute :condition, OmniSerializer::Types::Symbol | OmniSerializer::Types::Interface(:call).optional
  attribute :collection, OmniSerializer::Types::Bool
  attribute :resource, OmniSerializer::Types::String |
    OmniSerializer::Types::Hash.map(OmniSerializer::Types::Class, OmniSerializer::Types::String)

  def resource_class
    @resource_class ||= if resource.is_a?(Hash)
      resource.transform_values { |value| Object.const_get(value) }
    else
      Object.const_get(resource)
    end
  end
end
