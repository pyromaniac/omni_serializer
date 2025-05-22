# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::FieldsNormalizer do
  subject(:fields_normalizer) { described_class.new(key_formatter:, type_formatter:) }

  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }

  describe '#call' do
    subject(:result) { fields_normalizer.call(fields, included_resources:) }

    let(:fields) { {} }
    let(:included_resources) { [] }

    context 'when fields is nil' do
      let(:fields) { nil }

      specify do
        expect(result).to eq({})
      end
    end

    context 'when fields is empty' do
      let(:fields) { {} }

      specify do
        expect(result).to eq({})
      end
    end

    context 'when fields is an array' do
      let(:fields) { ['foobar'] }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`fields` parameter must be a mapping `{"type":"field1,field2"}`, given: `["foobar"]`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      end
    end

    context 'when fields is a string' do
      let(:fields) { 'foobar' }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`fields` parameter must be a mapping `{"type":"field1,field2"}`, given: `"foobar"`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      end
    end

    context 'when fields are given' do
      let(:fields) { { 'posts' => 'post-title', 'tags' => '', 'users' => 'user-name,post-tag-names' } }
      let(:included_resources) { [PostResource, TagResource, UserResource] }

      specify do
        expect(result).to match({
          PostResource => [be_a(OmniSerializer::Resource::Member) & have_attributes(name: :post_title)],
          TagResource => [],
          UserResource => [
            be_a(OmniSerializer::Resource::Member) & have_attributes(name: :user_name),
            be_a(OmniSerializer::Resource::Member) & have_attributes(name: :post_tag_names)
          ]
        })
      end
    end

    context 'when fields are invalid' do
      let(:fields) { { 'posts' => 'post-title,post_content' } }
      let(:included_resources) { [PostResource] }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Undefined member `post_content` for `posts`, ' \
            'valid members are: `id`, `post-title`, `post-content`, `tag-names`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      end
    end
  end
end
