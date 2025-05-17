# frozen_string_literal: true

# Provides cached loader instance to the context for the Dataloader pattern to work.
class OmniSerializer::Loaders
  extend Dry::Initializer

  param :loaders, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Class)

  def initialize(...)
    super
    @cache = {}
  end

  def method_missing(name, *, **)
    if loaders.key?(name)
      loader(name, *, **)
    else
      super
    end
  end

  def respond_to_missing?(name, include_private = false)
    loaders.key?(name) || super
  end

  def loader(name, *, **)
    loader_class = loaders.fetch(name)
    cache_key = cache_key(loader_class, *, **)

    @cache[cache_key] ||= begin
      loader = loader_class.new(*, **)
      OmniSerializer::Dataloader.new { |keys| loader.call(keys) }
    end
  end

  private

  def cache_key(loader_class, *, **)
    if loader_class.respond_to?(:cache_key)
      [loader_class, loader_class.cache_key(*, **)]
    else
      [loader_class, *, **]
    end
  end
end
