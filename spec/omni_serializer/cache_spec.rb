# frozen_string_literal: true

RSpec.describe OmniSerializer::Cache do
  describe '#initialize' do
    it 'initializes with an empty cache' do
      cache = described_class.new
      expect(cache.instance_variable_get(:@cache)).to eq({})
    end
  end

  describe '#fetch' do
    subject { described_class.new }

    let(:key) { 'test_key' }

    context 'when the key is not in the cache' do
      let(:computed_value) { 'computed_value' }

      it 'computes and stores the value' do
        block_called = false
        result = subject.fetch(key) do
          block_called = true
          computed_value
        end

        expect(result).to eq(computed_value)
        expect(block_called).to be true
        expect(subject.instance_variable_get(:@cache)[key]).to eq(computed_value)
      end
    end

    context 'when the key is already in the cache' do
      let(:cached_value) { 'cached_value' }

      before do
        subject.instance_variable_get(:@cache)[key] = cached_value
      end

      it 'returns the cached value without calling the block' do
        block_called = false
        result = subject.fetch(key) do
          block_called = true
          'new_value'
        end

        expect(result).to eq(cached_value)
        expect(block_called).to be false
      end
    end
  end
end
