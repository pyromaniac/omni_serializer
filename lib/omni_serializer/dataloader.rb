# frozen_string_literal: true

require 'concurrent'

# Dataloader pattern implementation for OmniSerializer using Concurrent::Promises.
class OmniSerializer::Dataloader
  def self.promises_executor
    @promises_executor ||= :io
  end

  def self.with_promises_executor(executor)
    old_executor = @promises_executor
    @promises_executor = executor
    yield
  ensure
    @promises_executor = old_executor
  end

  def initialize(executor = self.class.promises_executor, &resolver)
    @executor = executor
    @resolver = resolver
    @mutex = Mutex.new
    flush
  end

  def load(key)
    @mutex.synchronize do
      @keys.push(key)
      @promise.then(key) { |results, loaded_key| results.fetch(loaded_key) }
    end
  end

  def load_many(keys)
    @mutex.synchronize do
      @keys.concat(keys)
      @promise.then(keys) { |results, loaded_keys| results.fetch_values(*loaded_keys) }
    end
  end

  def resolve
    keys_batch = @mutex.synchronize { flush }
    @resolver.call(keys_batch)
  end

  private

  def flush
    keys = @keys.dup
    @keys = Concurrent::Array.new
    @promise = Concurrent::Promises.delay_on(@executor, self, &:resolve)
    keys
  end
end
