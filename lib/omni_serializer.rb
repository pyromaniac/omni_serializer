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
require 'omni_serializer/name_formatter'
require 'omni_serializer/evaluator'
require 'omni_serializer/simple'
require 'omni_serializer/simple/query_builder'
require 'omni_serializer/jsonapi'
require 'omni_serializer/jsonapi/query_builder'
require 'omni_serializer/jsonapi/deserializer'

module OmniSerializer
  class Error < StandardError; end

  class JsonapiError < Error
    attr_reader :error_data

    def initialize(detail:, status: 400, **error_data)
      super(detail)
      @error_data = error_data.merge(detail:, status:)
    end

    def status
      @error_data[:status]
    end
  end
end
