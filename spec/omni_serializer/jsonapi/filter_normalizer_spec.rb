# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::FilterNormalizer do
  subject(:filter_normalizer) { described_class.new(key_formatter:, type_formatter:, type_extractor:) }

  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }
  let(:type_extractor) { ->(name) { name.split(':', 2) } }

  describe '#call' do
    subject(:result) { filter_normalizer.call(resource_class, filter) }

    let(:resource_class) { PostResource }

    context 'when fields is nil' do
      let(:filter) { nil }

      it { is_expected.to eq({}) }
    end

    context 'when filter is empty' do
      let(:filter) { {} }

      it { is_expected.to eq({}) }
    end

    context 'when filter is an array' do
      let(:filter) { [] }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`filter` parameter must be a mapping, given: `[]`',
          status: 400,
          source: { parameter: 'filter' }
        }))
      end
    end

    context 'when filtering by member' do
      let(:filter) { { 'post-title' => 'foo' } }

      it { is_expected.to match([] => { post_title: 'foo' }) }

      context 'when filtering with array' do
        let(:filter) { { 'post-title' => %w[foo bar] } }

        it { is_expected.to match([] => { post_title: %w[foo bar] }) }
      end

      context 'when member is not defined' do
        let(:filter) { { 'postTitle' => 'foo' } }

        it { is_expected.to match([] => { postTitle: 'foo' }) }
      end
    end

    context 'when filtering by defined member with nested filter' do
      let(:filter) { { 'post-title' => { 'eq' => 'foo' } } }

      it { is_expected.to match([] => { post_title: { 'eq' => 'foo' } }) }

      context 'with dot-separated path' do
        let(:filter) { { 'post-title.eq' => 'foo' } }

        it { is_expected.to match([] => { post_title: { 'eq' => 'foo' } }) }
      end

      context 'with dot-separated path with dot-separated filter' do
        let(:filter) { { 'post-title.eq.value' => 'foo' } }

        it { is_expected.to match([] => { post_title: { 'eq' => { 'value' => 'foo' } } }) }
      end

      context 'when member is not defined' do
        let(:filter) { { 'foo-bar' => { 'eq.value' => 'foo' } } }

        it { is_expected.to match([] => { 'foo-bar': { 'eq' => { 'value' => 'foo' } } }) }
      end
    end

    context 'when filtering by defined member on association' do
      let(:filter) { { 'post-author' => { 'user-name' => 'Bruce Wayne' } } }

      it { is_expected.to match([[PostResource, :post_author]] => { user_name: 'Bruce Wayne' }) }

      context 'with collection association' do
        let(:filter) { { 'active-comments' => { 'comment-body' => 'hello' } } }

        it { is_expected.to match([[PostResource, :active_comments]] => { comment_body: 'hello' }) }
      end

      context 'with dot-separated path' do
        let(:filter) { { 'post-author.user-name' => 'Bruce Wayne' } }

        it { is_expected.to match([[PostResource, :post_author]] => { user_name: 'Bruce Wayne' }) }
      end

      context 'with dot-separated path with filter' do
        let(:filter) { { 'post-author.user-name.eq' => 'Bruce Wayne' } }

        it { is_expected.to match([[PostResource, :post_author]] => { user_name: { 'eq' => 'Bruce Wayne' } }) }
      end

      context 'with dot-separated path with filter and dot-separated path' do
        let(:filter) { { 'post-author.user-name' => { 'eq.value' => 'Bruce Wayne' } } }

        specify do
          expect(result).to match(
            [[PostResource, :post_author]] => { user_name: { 'eq' => { 'value' => 'Bruce Wayne' } } }
          )
        end
      end

      context 'when association name is invalid' do
        let(:filter) { { 'postAuthor' => { 'user-name' => 'Bruce Wayne' } } }

        it { is_expected.to match([] => { postAuthor: { 'user-name' => 'Bruce Wayne' } }) }
      end

      context 'when scalar filter directly on association' do
        let(:filter) { { 'post-author' => 42 } }

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid filter on `post-author` relationship, must be a mapping, given: `42`',
            status: 400,
            source: { parameter: 'filter' }
          }))
        end
      end

      context 'when scalar filter directly on association with dot-separated path' do
        let(:filter) { { 'active-comments.comment-author' => 42 } }

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid filter on `comment-author` relationship, must be a mapping, given: `42`',
            status: 400,
            source: { parameter: 'filter' }
          }))
        end
      end
    end

    context 'when filtering by deep association' do
      let(:filter) { { 'post-author.comments' => { 'comment-body' => 'hello' } } }

      specify do
        expect(result).to match([[PostResource, :post_author], [UserResource, :comments]] => { comment_body: 'hello' })
      end

      context 'with collection member association' do
        let(:filter) { { 'active-comments.comment-author' => { 'user-name' => 'Bruce Wayne' } } }

        specify do
          expect(result).to match([
            [PostResource, :active_comments],
            [CommentResource, :comment_author]
          ] => { user_name: 'Bruce Wayne' })
        end
      end
    end

    context 'with mergeable paths' do
      let(:filter) { { 'post-title.filter' => 42, 'post-title.value' => 43 } }

      it { is_expected.to match([] => { post_title: { 'filter' => 42, 'value' => 43 } }) }

      context 'when filtering by deep association' do
        let(:filter) { { 'post-author' => { 'user-name.value' => 43, 'user-name.eq' => 44 } } }

        it { is_expected.to match([[PostResource, :post_author]] => { user_name: { 'value' => 43, 'eq' => 44 } }) }
      end

      context 'when deep associations are in array' do
        let(:filter) { { 'active-comments.comment-body.eq.value' => 42, 'active-comments.comment-body' => 43 } }

        specify do
          expect(result).to match(
            [[PostResource, :active_comments]] => { comment_body: 43 }
          )
        end
      end
    end

    context 'when conflicting values are given' do
      let(:filter) { { 'post-title.eq' => 42, 'post-title.eq.value' => 43 } }

      it { is_expected.to match([] => { post_title: { 'eq' => { 'value' => 43 } } }) }
    end

    context 'when filtering polymorphic associations' do
      let(:resource_class) { TagResource }
      let(:filter) { { 'taggables' => { 'post-title' => 'value' } } }

      it { is_expected.to match([[TagResource, :taggables]] => { post_title: 'value', 'post-title': 'value' }) }

      context 'when members for all types are used' do
        let(:filter) do
          {
            'taggables.tags.name' => 'value1',
            'taggables.post-author.user-name' => 'value2',
            'taggables.post-title' => 'value3',
            'taggables.comment-body' => 'value4',
            'taggables.postAuthor' => 'value5'
          }
        end

        specify do
          expect(result).to match(
            [[TagResource, :taggables], [PostResource, :tags]] => { name: 'value1' },
            [[TagResource, :taggables], [CommentResource, :tags]] => { name: 'value1' },
            [[TagResource, :taggables], [PostResource, :post_author]] => { user_name: 'value2' },
            [[TagResource, :taggables]] => {
              'post-author': { 'user-name' => 'value2' },
              post_title: 'value3',
              comment_body: 'value4',
              'post-title': 'value3',
              'comment-body': 'value4',
              postAuthor: 'value5'
            }
          )
        end
      end

      context 'when filtering by deep association' do
        let(:filter) { { 'taggables.post-author' => { 'user-name' => 'value' } } }

        specify do
          expect(result).to match(
            [[TagResource, :taggables], [PostResource, :post_author]] => { user_name: 'value' },
            [[TagResource, :taggables]] => { 'post-author': { 'user-name' => 'value' } }
          )
        end
      end

      context 'when filtering by deep association with type specified' do
        let(:filter) { { 'taggables:posts.post-author' => { 'user-name' => 'value' } } }

        it { is_expected.to match([[TagResource, :taggables], [PostResource, :post_author]] => { user_name: 'value' }) }
      end

      context 'when all types are specified' do
        let(:filter) do
          {
            'taggables:posts' => { 'post-title' => 'value1' },
            'taggables:comments' => { 'comment-body' => 'value2' }
          }
        end

        it { is_expected.to match([[TagResource, :taggables]] => { post_title: 'value1', comment_body: 'value2' }) }
      end

      context 'when filtering by deep association with all types specified' do
        let(:filter) do
          {
            'taggables:posts.post-author' => { 'user-name' => 'value1' },
            'taggables:comments.comment-author' => { 'user-name' => 'value2' }
          }
        end

        specify do
          expect(result).to match(
            [[TagResource, :taggables], [PostResource, :post_author]] => { user_name: 'value1' },
            [[TagResource, :taggables], [CommentResource, :comment_author]] => { user_name: 'value2' }
          )
        end
      end

      context 'with invalid type' do
        let(:filter) { { 'taggables:Posts.post-author' => { 'user-name' => 'value' } } }

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type `Posts` for filter on `taggables`, valid types are: `posts`, `comments`',
            status: 400,
            source: { parameter: 'filter' }
          }))
        end
      end
    end
  end
end
