# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::PageNormalizer do
  subject(:page_normalizer) do
    described_class.new(
      'page',
      key_formatter:,
      type_formatter:,
      type_extractor:,
      allowed_keys:,
      missing_key_formatter:
    )
  end

  let(:allowed_keys) { %i[number size cursor before after] }
  let(:missing_key_formatter) do
    OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, casing: :snake, symbolize: true)
  end
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, casing: :kebab) }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, casing: :kebab, number: :plural) }
  let(:type_extractor) { ->(name) { name.split(':', 2) } }

  describe '#call' do
    subject(:normalized) { page_normalizer.call(resource_class, page) }

    let(:resource_class) { PostResource }
    let(:page) { nil }

    context 'when page is nil' do
      let(:page) { nil }

      it 'returns an empty map' do
        expect(normalized).to eq({})
      end
    end

    context 'when leaf keys are given' do
      let(:page) { { number: 2, size: 10 } }

      it 'stores leaf at root path' do
        expect(normalized).to eq([] => { number: 2, size: 10 })
      end
    end

    context 'when relationship and leaf are given' do
      let(:page) { { number: 2, tags: { cursor: '123' } } }

      it 'stores leaf at both paths' do
        expect(normalized).to eq(
          [] => { number: 2 },
          [[PostResource, :tags]] => { cursor: '123' }
        )
      end
    end

    context 'when dotted relationship path is given' do
      let(:resource_class) { UserResource }
      let(:page) { { 'posts.active-comments' => { number: 2, size: 10 } } }

      it 'stores leaf at nested relationship path' do
        expect(normalized).to eq(
          [[UserResource, :posts], [PostResource, :active_comments]] => { number: 2, size: 10 }
        )
      end
    end

    context 'when the collection member is polymorphic' do
      let(:resource_class) { TaggableCollectionResource }
      let(:page) { { tags: { number: 2, size: 10 } } }

      it 'stores the leaf under each type the collection serves' do
        expect(normalized).to eq(
          [[PostResource, :tags]] => { number: 2, size: 10 },
          [[CommentResource, :tags]] => { number: 2, size: 10 }
        )
      end
    end

    context 'when resource has reserved names' do
      before do
        stub_const(
          'PaginationClashResource',
          Class.new(OmniSerializer::Resource) do
            type { 'pagination-clash' }

            attribute :id
            attribute :number
            has_one :cursor, resource: 'PostResource'
            has_many :before, resource: 'PostResource'
          end
        )
      end

      let(:resource_class) { PaginationClashResource }

      context 'when reserved leaf keys are used' do
        let(:page) { { number: 1, cursor: 'c', before: 'b' } }

        it 'does not clash with resource members' do
          expect(normalized).to eq([] => { number: 1, cursor: 'c', before: 'b' })
        end
      end

      context 'when reserved key is used as relationship' do
        let(:page) { { cursor: { number: 42 } } }

        it 'allows relationship pagination' do
          expect(normalized).to eq([[PaginationClashResource, :cursor]] => { number: 42 })
        end
      end
    end

    context 'when page is not a mapping' do
      let(:page) { 'foo' }

      it 'raises a parameter error' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page parameter at `/`, must be a mapping with keys: ' \
              '`number`, `size`, `cursor`, `before`, `after`, given: `"foo"`',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end

    context 'when unknown leaf key is given' do
      let(:page) { { number: 42, foo: 'bar' } }

      it 'raises a key error' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page key at `/`, allowed keys are: ' \
              '`number`, `size`, `cursor`, `before`, `after`, given: `{"foo":"bar"}`',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end

    context 'when relationship segment is unknown' do
      let(:page) { { 'postAuthor' => { 'number' => 1 } } }

      it 'raises a relationship error' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page relationship `postAuthor` at `/postAuthor`, valid relationships are: ' \
              '`post-author`, `active-comments`, `taggings`, `tags`',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end

    context 'when relationship has scalar value' do
      let(:page) { { 'tags' => 1 } }

      it 'raises a parameter error' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page parameter at `/tags`, must be a mapping with keys: ' \
              '`number`, `size`, `cursor`, `before`, `after`, given: `1`',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end

    context 'when relationship has invalid leaf key' do
      let(:page) { { 'tags' => { 'foo' => 1 } } }

      it 'raises a key error at relationship path' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page key at `/tags`, allowed keys are: ' \
              '`number`, `size`, `cursor`, `before`, `after`, given: `{"foo":1}`',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end

    context 'when type suffix is used' do
      let(:resource_class) { TaggingResource }
      let(:page) { { 'taggable:posts' => { 'number' => 1 } } }

      it 'rejects type scoping' do
        expect { normalized }
          .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid page relationship `taggable:posts` at `/taggable:posts`, ' \
              'type scoping is not supported for pagination',
            status: 400,
            source: { parameter: 'page' }
          }))
      end
    end
  end
end
