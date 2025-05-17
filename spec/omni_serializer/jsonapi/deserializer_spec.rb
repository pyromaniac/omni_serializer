# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::Deserializer do
  subject(:deserializer) { described_class.new(missing_key_formatter:, key_formatter:, type_formatter:) }

  let(:missing_key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, casing: :snake) }
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }

  describe '#call' do
    subject(:result) { deserializer.call(resource_class, data) }

    let(:resource_class) { PostResource }

    context 'with invalid top-level type' do
      let(:data) { { type: 'Posts' } }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid type given: `Posts`, valid types are: `posts`.',
          status: 409,
          source: { pointer: '/data/type' }
        }))
      end
    end

    context 'with malformed root data' do
      let(:data) { { id: 42, type: 'posts' } }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Malformed root data, should be an object with string `id` (optional), `type` and other members.',
          status: 400,
          source: { pointer: '/data' }
        }))
      end
    end

    context 'with missing root data' do
      let(:data) { nil }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Malformed root data, should be an object with string `id` (optional), `type` and other members.',
          status: 400,
          source: { pointer: '/data' }
        }))
      end
    end

    context 'with valid type' do
      let(:data) { { type: 'posts' } }

      specify do
        expect(result).to have_attributes(
          params: {},
          pointers: { [] => '/data', [:id] => '/data/id', [:type] => '/data/type' }
        )
      end
    end

    context 'with type and id' do
      let(:data) { { id: '42', type: 'posts' } }

      specify do
        expect(result).to have_attributes(
          params: { id: '42' },
          pointers: { [] => '/data', [:id] => '/data/id', [:type] => '/data/type' }
        )
      end
    end

    context 'with attributes' do
      let(:data) do
        {
          id: '42',
          type: 'posts',
          attributes: {
            title: 'Hello, world!',
            'post-content': 'Lorem ipsum',
            'non-existing': 'Will be processed'
          }
        }
      end

      specify do
        expect(result).to have_attributes(
          params: {
            id: '42',
            title: 'Hello, world!',
            post_content: 'Lorem ipsum',
            non_existing: 'Will be processed'
          },
          pointers: {
            [] => '/data',
            [:id] => '/data/id',
            [:type] => '/data/type',
            [:title] => '/data/attributes/title',
            [:post_content] => '/data/attributes/post-content',
            [:non_existing] => '/data/attributes/non-existing'
          }
        )
      end
    end

    context 'with relationship given as an attribute' do
      let(:data) do
        {
          type: 'posts',
          attributes: { 'post-author': '42' }
        }
      end

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Relationship `post-author` on `posts` given as an attribute, please move it under `relationships`.',
          status: 400,
          source: { pointer: '/data/attributes/post-author' }
        }))
      end
    end

    context 'with non-existent relationship' do
      let(:data) do
        {
          type: 'posts',
          relationships: { 'non-existent': { data: { id: '42', type: 'users' } } }
        }
      end

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Relationship `non-existent` is not defined on `posts`, ' \
            'valid relationships are: `post-author`, `active-comments`, `taggings`, `tags`.',
          status: 400,
          source: { pointer: '/data/relationships/non-existent' }
        }))
      end
    end

    context 'with singular relationship' do
      let(:data) do
        {
          type: 'posts',
          relationships: {
            'post-author': { data: { id: '42', type: 'users' } }
          }
        }
      end

      specify do
        expect(result).to have_attributes(
          params: {
            post_author_id: '42'
          },
          pointers: {
            [] => '/data',
            [:id] => '/data/id',
            [:type] => '/data/type',
            [:post_author_id] => '/data/relationships/post-author/data/id'
          }
        )
      end

      context 'with nil data' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'post-author': { data: nil } }
          }
        end

        specify do
          expect(result).to have_attributes(
            params: { post_author_id: nil },
            pointers: {
              [] => '/data',
              [:id] => '/data/id',
              [:type] => '/data/type',
              [:post_author_id] => '/data/relationships/post-author/data'
            }
          )
        end
      end

      context 'with invalid type' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'post-author': { data: { id: '42', type: 'post-authors' } } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type given: `post-authors`, valid types are: `users`.',
            status: 409,
            source: { pointer: '/data/relationships/post-author/data/type' }
          }))
        end
      end

      context 'with malformed data' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'post-author': { data: { type: 'users' } } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `post-author` relationship, ' \
              'should be an object with string `id` and `type` or null.',
            status: 400,
            source: { pointer: '/data/relationships/post-author/data' }
          }))
        end
      end
    end

    context 'with singular polymorphic relationship' do
      let(:resource_class) { TaggingResource }
      let(:data) do
        {
          type: 'taggings',
          relationships: {
            taggable: { data: { id: '42', type: 'posts' } }
          }
        }
      end

      specify do
        expect(result).to have_attributes(
          params: {
            taggable_id: '42',
            taggable_type: 'Post'
          },
          pointers: {
            [] => '/data',
            [:id] => '/data/id',
            [:type] => '/data/type',
            [:taggable_id] => '/data/relationships/taggable/data/id',
            [:taggable_type] => '/data/relationships/taggable/data/type'
          }
        )
      end

      context 'with nil data' do
        let(:data) do
          {
            type: 'taggings',
            relationships: {
              taggable: { data: nil }
            }
          }
        end

        specify do
          expect(result).to have_attributes(
            params: { taggable_id: nil },
            pointers: {
              [] => '/data',
              [:id] => '/data/id',
              [:type] => '/data/type',
              [:taggable_id] => '/data/relationships/taggable/data'
            }
          )
        end
      end

      context 'with invalid type' do
        let(:data) do
          {
            type: 'taggings',
            relationships: {
              taggable: { data: { id: '42', type: 'taggables' } }
            }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type given: `taggables`, valid types are: `posts`, `comments`.',
            status: 409,
            source: { pointer: '/data/relationships/taggable/data/type' }
          }))
        end
      end

      context 'with malformed data' do
        let(:data) do
          {
            type: 'taggings',
            relationships: { taggable: { data: { id: '42', type: 'posts', unexpected: 'key' } } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `taggable` relationship, ' \
              'should be an object with string `id` and `type` or null.',
            status: 400,
            source: { pointer: '/data/relationships/taggable/data' }
          }))
        end
      end
    end

    context 'with collection relationship' do
      let(:resource_class) { PostResource }
      let(:data) do
        {
          type: 'posts',
          relationships: {
            'active-comments': { data: [
              { id: '42', type: 'comments' },
              { id: '43', type: 'comments' }
            ] }
          }
        }
      end

      specify do
        expect(result).to have_attributes(
          params: { active_comment_ids: %w[42 43] },
          pointers: {
            [] => '/data',
            [:id] => '/data/id',
            [:type] => '/data/type',
            [:active_comment_ids] => '/data/relationships/active-comments/data',
            [:active_comment_ids, 0] => '/data/relationships/active-comments/data/0/id',
            [:active_comment_ids, 1] => '/data/relationships/active-comments/data/1/id'
          }
        )
      end

      context 'with empty data' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'active-comments': { data: [] } }
          }
        end

        specify do
          expect(result).to have_attributes(
            params: { active_comment_ids: [] },
            pointers: {
              [] => '/data',
              [:id] => '/data/id',
              [:type] => '/data/type',
              [:active_comment_ids] => '/data/relationships/active-comments/data'
            }
          )
        end
      end

      context 'with invalid type' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'active-comments': { data: [{ id: '42', type: 'Comments' }] } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type given: `Comments`, valid types are: `comments`.',
            status: 409,
            source: { pointer: '/data/relationships/active-comments/data/0/type' }
          }))
        end
      end

      context 'with malformed data' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'active-comments': { data: {} } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `active-comments` relationship, ' \
              'should be an array of objects with string `id` and `type`.',
            status: 400,
            source: { pointer: '/data/relationships/active-comments/data' }
          }))
        end
      end

      context 'with malformed datum' do
        let(:data) do
          {
            type: 'posts',
            relationships: { 'active-comments': { data: [{ id: '42', type: 'comments' }, nil] } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `active-comments` relationship datum, ' \
              'should be an object with string `id` and `type`.',
            status: 400,
            source: { pointer: '/data/relationships/active-comments/data/1' }
          }))
        end
      end
    end

    context 'with polymorphic collection relationship' do
      let(:resource_class) { TagResource }
      let(:data) do
        {
          type: 'tags',
          relationships: {
            taggables: { data: [
              { id: '42', type: 'posts' },
              { id: '43', type: 'comments' }
            ] }
          }
        }
      end

      specify do
        expect(result).to have_attributes(
          params: {
            taggables: [
              { id: '42', type: 'Post' },
              { id: '43', type: 'Comment' }
            ]
          },
          pointers: {
            [] => '/data',
            [:id] => '/data/id',
            [:type] => '/data/type',
            [:taggables] => '/data/relationships/taggables/data',
            [:taggables, 0] => '/data/relationships/taggables/data/0',
            [:taggables, 1] => '/data/relationships/taggables/data/1',
            [:taggables, 0, :id] => '/data/relationships/taggables/data/0/id',
            [:taggables, 1, :id] => '/data/relationships/taggables/data/1/id',
            [:taggables, 0, :type] => '/data/relationships/taggables/data/0/type',
            [:taggables, 1, :type] => '/data/relationships/taggables/data/1/type'
          }
        )
      end

      context 'with empty data' do
        let(:data) do
          {
            type: 'tags',
            relationships: { taggables: { data: [] } }
          }
        end

        specify do
          expect(result).to have_attributes(
            params: { taggables: [] },
            pointers: {
              [] => '/data',
              [:id] => '/data/id',
              [:type] => '/data/type',
              [:taggables] => '/data/relationships/taggables/data'
            }
          )
        end
      end

      context 'with invalid type' do
        let(:data) do
          {
            type: 'tags',
            relationships: { taggables: { data: [{ id: '42', type: 'posts' }, { id: '43', type: 'users' }] } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type given: `users`, valid types are: `posts`, `comments`.',
            status: 409,
            source: { pointer: '/data/relationships/taggables/data/1/type' }
          }))
        end
      end

      context 'with malformed data' do
        let(:data) do
          {
            type: 'tags',
            relationships: { taggables: { data: nil } }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `taggables` relationship, ' \
              'should be an array of objects with string `id` and `type`.',
            status: 400,
            source: { pointer: '/data/relationships/taggables/data' }
          }))
        end
      end

      context 'with malformed datum' do
        let(:data) do
          {
            type: 'tags',
            relationships: {
              taggables: {
                data: [
                  { id: '42', type: 'posts' },
                  { id: '43', type: 'comments', unexpected: 'key' }
                ]
              }
            }
          }
        end

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Malformed data for `taggables` relationship datum, ' \
              'should be an object with string `id` and `type`.',
            status: 400,
            source: { pointer: '/data/relationships/taggables/data/1' }
          }))
        end
      end
    end
  end
end
