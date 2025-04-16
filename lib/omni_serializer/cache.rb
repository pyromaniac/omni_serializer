# frozen_string_literal: true

class OmniSerializer::Cache
  def initialize
    @cache = {}
  end

  def fetch(key)
    @cache.fetch(key) do |key|
      @cache[key] = yield
    end
  end
end
