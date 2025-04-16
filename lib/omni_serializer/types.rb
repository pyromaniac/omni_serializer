# frozen_string_literal: true

require 'dry-types'

# Dry::Types for the gem.
module OmniSerializer::Types
  include Dry::Types()

  Resource = Class.constrained(respond_to: :members)
  Transform = Symbol.enum(:camel, :camel_lower, :dash, :underscore).optional
end
