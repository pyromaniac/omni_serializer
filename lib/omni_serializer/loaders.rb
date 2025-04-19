# frozen_string_literal: true

require 'dataloader'

class OmniSerializer::Loaders
  extend Dry::Initializer

  param :loaders, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Class)

  def initialize(...)
    super
    @cache = {}
  end

  def loader(name, *args, **kwargs)
    loader_class = @loaders.fetch(name)
    cache_key = [loader_class, args, kwargs]

    @cache[cache_key] ||= begin
      loader = loader_class.new(*args, **kwargs)
      Dataloader.new { |keys| loader.call(keys) }
    end
  end
end
