# frozen_string_literal: true

RSpec.describe OmniSerializer::Loaders do
  subject { described_class.new(loader_classes) }

  let(:loader_classes) { { user: Class.new, post: Class.new } }

  describe '#initialize' do
    it 'initializes with the loader classes hash' do
      expect(subject.loaders).to eq(loader_classes)
    end
  end
end
