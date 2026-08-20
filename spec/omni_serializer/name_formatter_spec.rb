# frozen_string_literal: true

RSpec.describe OmniSerializer::NameFormatter do
  subject(:formatter) { described_class.new(inflector: Dry::Inflector.new, **options) }

  let(:options) { {} }

  describe '#call' do
    specify do
      expect(formatter.call('omni_serializer')).to eq('omni_serializer')
      expect(formatter.call('OmniSerializer')).to eq('OmniSerializer')
      expect(formatter.call('omniSerializer')).to eq('omniSerializer')
      expect(formatter.call('omni-serializer')).to eq('omni-serializer')
    end

    context 'when casing is :camel' do
      let(:options) { { casing: :camel } }

      specify do
        expect(formatter.call('OmniSerializer::NameFormatter')).to eq('omniSerializerNameFormatter')
        expect(formatter.call('omni_serializer/name_formatter')).to eq('omniSerializerNameFormatter')
        expect(formatter.call('OmniSerializer')).to eq('omniSerializer')
        expect(formatter.call('OmniSerializers')).to eq('omniSerializers')
        expect(formatter.call('omni_serializer')).to eq('omniSerializer')
        expect(formatter.call('omni_serializers')).to eq('omniSerializers')
      end
    end

    context 'when casing is :kebab' do
      let(:options) { { casing: :kebab } }

      specify do
        expect(formatter.call('OmniSerializer::NameFormatter')).to eq('omni-serializer-name-formatter')
        expect(formatter.call('omni_serializer/name_formatter')).to eq('omni-serializer-name-formatter')
        expect(formatter.call('OmniSerializer')).to eq('omni-serializer')
        expect(formatter.call('OmniSerializers')).to eq('omni-serializers')
        expect(formatter.call('omni_serializer')).to eq('omni-serializer')
        expect(formatter.call('omni_serializers')).to eq('omni-serializers')
      end
    end

    context 'when casing is :pascal' do
      let(:options) { { casing: :pascal } }

      specify do
        expect(formatter.call('OmniSerializer::NameFormatter')).to eq('OmniSerializerNameFormatter')
        expect(formatter.call('omni_serializer/name_formatter')).to eq('OmniSerializerNameFormatter')
        expect(formatter.call('OmniSerializer')).to eq('OmniSerializer')
        expect(formatter.call('OmniSerializers')).to eq('OmniSerializers')
        expect(formatter.call('omni_serializer')).to eq('OmniSerializer')
        expect(formatter.call('omni_serializers')).to eq('OmniSerializers')
      end
    end

    context 'when casing is :snake' do
      let(:options) { { casing: :snake } }

      specify do
        expect(formatter.call('OmniSerializer::NameFormatter')).to eq('omni_serializer_name_formatter')
        expect(formatter.call('omni_serializer/name_formatter')).to eq('omni_serializer_name_formatter')
        expect(formatter.call('OmniSerializer')).to eq('omni_serializer')
        expect(formatter.call('OmniSerializers')).to eq('omni_serializers')
        expect(formatter.call('omni_serializer')).to eq('omni_serializer')
        expect(formatter.call('omni_serializers')).to eq('omni_serializers')
      end
    end
  end
end
