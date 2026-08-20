# frozen_string_literal: true

class OmniSerializer::Resource::Association < Dry::Struct
  MODEL_REFERENCE = OmniSerializer::Types::Class | OmniSerializer::Types::String
  RESOURCE_REFERENCE = OmniSerializer::Types::Resource | OmniSerializer::Types::String

  attribute :name, OmniSerializer::Types::Symbol
  attribute :evaluator, OmniSerializer::Types::Interface(:call).optional
  attribute :condition, OmniSerializer::Types::Symbol | OmniSerializer::Types::Interface(:call).optional
  attribute :collection, OmniSerializer::Types::Bool
  attribute :resource, RESOURCE_REFERENCE | OmniSerializer::Types::Hash.map(MODEL_REFERENCE, RESOURCE_REFERENCE)

  def polymorphic?
    resource.is_a?(Hash)
  end

  def resource_classes
    @resource_classes ||= polymorphic? ? resolved_resource.values : [resolved_resource]
  end

  def resolved_resource
    @resolved_resource ||= if polymorphic?
      resource.to_h do |model_reference, resource_reference|
        [resolve_reference(model_reference), resolve_reference(resource_reference)]
      end
    else
      resolve_reference(resource)
    end
  end

  private

  def resolve_reference(reference)
    reference.is_a?(String) ? Object.const_get(reference) : reference
  end
end
