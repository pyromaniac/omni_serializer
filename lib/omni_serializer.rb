# frozen_string_literal: true

require 'dry-initializer'
require 'dry-struct'
require 'omni_serializer/version'
require 'omni_serializer/types'
require 'omni_serializer/inspect'
require 'omni_serializer/utils'
require 'omni_serializer/cache'
require 'omni_serializer/loaders'
require 'omni_serializer/resource'
require 'omni_serializer/resource/member'
require 'omni_serializer/resource/association'
require 'omni_serializer/query'
require 'omni_serializer/evaluator'
require 'omni_serializer/simple'
require 'omni_serializer/simple/query_builder'
require 'omni_serializer/jsonapi'
require 'omni_serializer/jsonapi/query_builder'

module OmniSerializer
  class Error < StandardError; end

  class UndefinedAssociation < Error
    attr_reader :resource_class, :name

    def initialize(resource_class, name)
      @resource_class = resource_class
      @name = name
      super("Undefined association: `#{name}` for `#{resource_class}`")
    end
  end

  class UndefinedAssociationType < Error
    attr_reader :resource_class, :name, :type

    def initialize(resource_class, name, type)
      @resource_class = resource_class
      @name = name
      @type = type
      super("Undefined association type: `#{type}` for `#{name}` on `#{resource_class}`")
    end
  end

  class UndefinedQueryType < Error
    attr_reader :type, :query_types

    def initialize(type, query_types)
      @type = type
      @query_types = query_types
      super("Undefined type: `#{type}`, query types: `#{query_types.join('`, `')}`")
    end
  end

  class UndefinedMember < Error
    attr_reader :resource_class, :name

    def initialize(resource_class, name)
      @resource_class = resource_class
      @name = name
      super("Undefined member: `#{name}` for `#{resource_class}`")
    end
  end
end
