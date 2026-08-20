# frozen_string_literal: true

RSpec.describe OmniSerializer::Loaders do
  subject(:loaders) { described_class.new(loader_classes) }

  let(:collection_loader) do
    Class.new do
      def initialize(value)
        @value = value
      end

      def call(keys)
        keys.index_with { |key| { key:, value: @value } }
      end
    end
  end

  let(:loader_classes) { { collection: collection_loader } }

  describe '#loader' do
    it 'returns a cached loader instance' do
      expect(loaders.collection(42)).to be_a(OmniSerializer::Dataloader)
      expect(loaders.collection(42)).to equal(loaders.loader(:collection, 42))
      expect(loaders.collection(42)).not_to equal(loaders.collection(43))
    end

    it 'calls the loader with the correct arguments' do
      expect(loaders.loader(:collection, 42).load(:foo).value!)
        .to eq({ key: :foo, value: 42 })
      expect(loaders.collection(42).load_many(%i[foo bar]).value!)
        .to eq([{ key: :foo, value: 42 }, { key: :bar, value: 42 }])
    end
  end
end
