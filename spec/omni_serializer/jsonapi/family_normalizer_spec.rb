# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::FamilyNormalizer do
  subject(:family_normalizer) do
    described_class.new(param_key, key_formatter:, type_formatter:, type_extractor:, leaf_normalizer:)
  end

  let(:param_key) { 'foobar' }
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }
  let(:type_extractor) { ->(name) { name.split(':', 2) } }
  let(:leaf_normalizer) do
    lambda do |parent, value, **|
      value = { _leaf: value }
      value[:_on] = parent.name if parent
      value
    end
  end

  describe '#call' do
    subject(:result) { family_normalizer.call(resource_class, param) }

    let(:resource_class) { PostResource }

    context 'when fields is nil' do
      let(:param) { nil }

      it { is_expected.to eq({}) }
    end

    context 'when param is empty' do
      let(:param) { {} }

      it { is_expected.to eq({}) }
    end

    context 'when param is an array' do
      let(:param) { [] }

      it { is_expected.to eq({}) }
    end

    context 'when param is a string' do
      let(:param) { 'foo' }

      it { is_expected.to eq([] => { _leaf: 'foo', _on: 'PostResource' }) }
    end

    context 'when param on member' do
      let(:param) { { 'post-title' => 'foo' } }

      it { is_expected.to eq([] => { post_title: { _leaf: 'foo', _on: :post_title } }) }

      context 'when param is an array' do
        let(:param) { ['foo', { 'post-title' => 42 }, { 'postTitle' => 43 }] }

        specify do
          is_expected.to eq(
            [] => { _leaf: { 'postTitle' => 43 }, _on: 'PostResource', post_title: { _leaf: 42, _on: :post_title } }
          )
        end
      end

      context 'when value is array' do
        let(:param) { { 'post-title' => %w[foo bar] } }

        it { is_expected.to eq([] => { post_title: { _leaf: %w[foo bar], _on: :post_title } }) }
      end

      context 'when member is not defined' do
        let(:param) { { 'postTitle' => 'foo' } }

        it { is_expected.to eq([] => { _leaf: { 'postTitle' => 'foo' } }) }
      end
    end

    context 'when param on defined member with nested param' do
      let(:param) { { 'post-title' => { 'eq' => 'foo' } } }

      it { is_expected.to eq([] => { post_title: { _leaf: { 'eq' => 'foo' }, _on: :post_title } }) }

      context 'with dot-separated path' do
        let(:param) { { 'post-title.eq' => 'foo' } }

        it { is_expected.to eq([] => { post_title: { _leaf: { 'eq' => 'foo' }, _on: :post_title } }) }
      end

      context 'with dot-separated path with dot-separated param' do
        let(:param) { { 'post-title.eq.value' => 'foo' } }

        it { is_expected.to eq([] => { post_title: { _leaf: { 'eq' => { 'value' => 'foo' } }, _on: :post_title } }) }
      end

      context 'when member is not defined' do
        let(:param) { { 'postTitle' => { 'eq.value' => 'foo' } } }

        it { is_expected.to eq([] => { _leaf: { 'postTitle' => { 'eq' => { 'value' => 'foo' } } } }) }
      end
    end

    context 'when param on defined member on association' do
      let(:param) { { 'post-author' => { 'user-name' => 'Bruce Wayne' } } }

      specify do
        expect(result).to eq(
          [[PostResource, :post_author]] => { user_name: { _leaf: 'Bruce Wayne', _on: :user_name } }
        )
      end

      context 'with collection association' do
        let(:param) { { 'active-comments' => { 'comment-body' => 'hello' } } }

        specify do
          expect(result).to eq(
            [[PostResource, :active_comments]] => { comment_body: { _leaf: 'hello', _on: :comment_body } }
          )
        end
      end

      context 'when param is array' do
        let(:param) { { 'active-comments' => %w[foo bar] } }

        specify do
          expect(result).to eq(
            [[PostResource, :active_comments]] => { _leaf: %w[foo bar], _on: 'CommentCollectionResource' }
          )
        end
      end

      context 'when param is an array with accociation hashes' do
        let(:param) { ['foo', { 'active-comments' => 42 }, 'bar', { 'post-author' => 43 }] }

        specify do
          expect(result).to eq(
            [] => { _leaf: 'bar', _on: 'PostResource' },
            [[PostResource, :active_comments]] => { _leaf: 42, _on: 'CommentCollectionResource' },
            [[PostResource, :post_author]] => { _leaf: 43, _on: 'UserResource' }
          )
        end
      end

      context 'with dot-separated path' do
        let(:param) { { 'post-author.user-name' => 'Bruce Wayne' } }

        specify do
          expect(result).to eq(
            [[PostResource, :post_author]] => { user_name: { _leaf: 'Bruce Wayne', _on: :user_name } }
          )
        end
      end

      context 'with dot-separated path with param' do
        let(:param) { { 'post-author.user-name.eq' => 'Bruce Wayne' } }

        specify do
          is_expected.to eq(
            [[PostResource, :post_author]] => { user_name: { _leaf: { 'eq' => 'Bruce Wayne' }, _on: :user_name } }
          )
        end
      end

      context 'with dot-separated path with param and dot-separated path' do
        let(:param) { { 'post-author.user-name' => { 'eq.value' => 'Bruce Wayne' } } }

        specify do
          expect(result).to eq(
            [[PostResource, :post_author]] => {
              user_name: { _leaf: { 'eq' => { 'value' => 'Bruce Wayne' } }, _on: :user_name }
            }
          )
        end
      end

      context 'when association name is invalid' do
        let(:param) { { 'postAuthor' => { 'user-name' => 'Bruce Wayne' } } }

        it { is_expected.to eq([] => { _leaf: { 'postAuthor' => { 'user-name' => 'Bruce Wayne' } } }) }
      end

      context 'when scalar param directly on association' do
        let(:param) { { 'post-author' => 42 } }

        it { is_expected.to eq([[PostResource, :post_author]] => { _leaf: 42, _on: 'UserResource' }) }
      end

      context 'when scalar param directly on association with dot-separated path' do
        let(:param) { { 'active-comments.comment-author' => 42 } }

        specify do
          expect(result).to eq([
            [PostResource, :active_comments],
            [CommentResource, :comment_author]
          ] => { _leaf: 42, _on: 'UserResource' })
        end
      end
    end

    context 'when param on deep association' do
      let(:param) { { 'post-author.comments' => { 'comment-body' => 'hello' } } }

      specify do
        expect(result).to eq(
          [[PostResource, :post_author], [UserResource, :comments]] => {
            comment_body: { _leaf: 'hello', _on: :comment_body }
          }
        )
      end

      context 'with collection member association' do
        let(:param) { { 'active-comments.comment-author' => { 'user-name' => 'Bruce Wayne' } } }

        specify do
          expect(result).to eq([
            [PostResource, :active_comments],
            [CommentResource, :comment_author]
          ] => { user_name: { _leaf: 'Bruce Wayne', _on: :user_name } })
        end
      end
    end

    context 'with mergeable paths' do
      let(:param) { { 'post-title.eq' => 42, 'post-title.value' => 43 } }

      it { is_expected.to eq([] => { post_title: { _leaf: { 'eq' => 42, 'value' => 43 }, _on: :post_title } }) }

      context 'when param on deep association' do
        let(:param) { { 'post-author' => { 'user-name.value' => 43, 'user-name.eq' => 44 } } }

        specify do
          expect(result).to eq(
            [[PostResource, :post_author]] => {
              user_name: { _leaf: { 'value' => 43, 'eq' => 44 }, _on: :user_name }
            }
          )
        end
      end

      context 'when deep associations are in array' do
        let(:param) { { 'active-comments.comment-body.eq.value' => 42, 'active-comments.comment-body' => 43 } }

        specify do
          expect(result).to eq(
            [[PostResource, :active_comments]] => { comment_body: { _leaf: 43, _on: :comment_body } }
          )
        end
      end
    end

    context 'when conflicting values are given' do
      let(:param) { { 'post-title.eq' => 42, 'post-title.eq.value' => 43 } }

      it { is_expected.to eq([] => { post_title: { _leaf: { 'eq' => { 'value' => 43 } }, _on: :post_title } }) }
    end

    context 'when param onlymorphic associations' do
      let(:resource_class) { TagResource }
      let(:param) { { 'taggables' => { 'post-title' => 'value' } } }

      specify do
        expect(result).to eq(
          [[TagResource, :taggables]] => {
            post_title: { _leaf: 'value', _on: :post_title },
            _leaf: { 'post-title' => 'value' }
          }
        )
      end

      context 'when fields for all types are used' do
        let(:param) do
          {
            'taggables.tags.name' => 'value1',
            'taggables.post-author.user-name' => 'value2',
            'taggables.post-title' => 'value3',
            'taggables.comment-body' => 'value4',
            'taggables.postAuthor' => 'value5'
          }
        end

        specify do
          expect(p(result)).to eq(
            [[TagResource, :taggables], [CommentResource, :tags]] => { _leaf: { 'name' => 'value1' } },
            [[TagResource, :taggables], [PostResource, :tags]] => { _leaf: { 'name' => 'value1' } },
            [[TagResource, :taggables], [PostResource, :post_author]] => {
              user_name: { _leaf: 'value2', _on: :user_name }
            },
            [[TagResource, :taggables]] => {
              post_title: { _leaf: 'value3', _on: :post_title },
              comment_body: { _leaf: 'value4', _on: :comment_body },
              _leaf: { 'postAuthor' => 'value5' }
            }
          )
        end
      end

      context 'when param on deep association' do
        let(:param) { { 'taggables.post-author' => { 'user-name' => 'value' } } }

        specify do
          expect(result).to eq(
            [[TagResource, :taggables], [PostResource, :post_author]] => {
              user_name: { _leaf: 'value', _on: :user_name }
            },
            [[TagResource, :taggables]] => { _leaf: { 'post-author' => { 'user-name' => 'value' } } }
          )
        end
      end

      context 'when param on deep association with type specified' do
        let(:param) { { 'taggables:posts.post-author' => { 'user-name' => 'value' } } }

        specify do
          expect(result).to eq([[TagResource, :taggables], [PostResource, :post_author]] => {
            user_name: { _leaf: 'value', _on: :user_name }
          })
        end
      end

      context 'when all types are specified' do
        let(:param) do
          {
            'taggables:posts' => { 'post-title' => 'value1' },
            'taggables:comments' => { 'comment-body' => 'value2' }
          }
        end

        specify do
          expect(result).to eq([[TagResource, :taggables]] => {
            post_title: { _leaf: 'value1', _on: :post_title },
            comment_body: { _leaf: 'value2', _on: :comment_body }
          })
        end
      end

      context 'when param on deep association with all types specified' do
        let(:param) do
          {
            'taggables:posts.post-author' => { 'user-name' => 'value1' },
            'taggables:comments.comment-author' => { 'user-name' => 'value2' }
          }
        end

        specify do
          expect(result).to eq(
            [[TagResource, :taggables], [PostResource, :post_author]] => {
              user_name: { _leaf: 'value1', _on: :user_name }
            },
            [[TagResource, :taggables], [CommentResource, :comment_author]] => {
              user_name: { _leaf: 'value2', _on: :user_name }
            }
          )
        end
      end

      context 'with invalid type' do
        let(:param) { { 'taggables:Posts.post-author' => { 'user-name' => 'value' } } }

        specify do
          expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
            detail: 'Invalid type `Posts` for foobar on `taggables`, valid types are: `posts`, `comments`',
            status: 400,
            source: { parameter: 'foobar' }
          }))
        end
      end
    end
  end
end
