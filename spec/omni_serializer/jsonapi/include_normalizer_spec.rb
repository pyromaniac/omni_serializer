# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::IncludeNormalizer do
  subject(:include_normalizer) { described_class.new(key_formatter:, type_formatter:, type_extractor:) }

  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }
  let(:type_extractor) { ->(name) { name.split(':', 2) } }

  describe '#call' do
    subject(:result) { include_normalizer.call(resource_class, include) }

    let(:resource_class) { PostResource }

    context 'when include is nil' do
      let(:include) { nil }

      specify do
        expect(result).to eq({})
      end
    end

    context 'when include is empty' do
      let(:include) { '' }

      specify do
        expect(result).to eq({})
      end
    end

    context 'when include is a hash' do
      let(:include) { { 'foo' => 'bar' } }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`include` parameter must be a string `include1.include2,include3`, given: `{"foo":"bar"}`',
          status: 400,
          source: { parameter: 'include' }
        }))
      end
    end

    context 'when include is an array of non-string values' do
      let(:include) { ['foo', {}] }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`include` parameter must be a string `include1.include2,include3`, given: `["foo",{}]`',
          status: 400,
          source: { parameter: 'include' }
        }))
      end
    end

    context 'with one level includes' do
      let(:include) { 'post-author,active-comments,taggings,tags' }

      specify do
        expect(result).to eq({
          [:post_author, UserResource] => {},
          [:active_comments, CommentCollectionResource] => { [:to_a, CommentResource] => {} },
          [:taggings, TaggingResource] => {},
          [:tags, TagResource] => {}
        })
      end
    end

    context 'with multiple level includes' do
      let(:include) { 'post-author.comments,active-comments.comment-author.posts' }

      specify do
        expect(result).to eq({
          [:active_comments, CommentCollectionResource] => {
            [:to_a, CommentResource] => {
              [:comment_author, UserResource] => {
                [:posts, PostCollectionResource] => {
                  [:to_a, PostResource] => {}
                }
              }
            }
          },
          [:post_author, UserResource] => {
            [:comments, CommentCollectionResource] => { [:to_a, CommentResource] => {} }
          }
        })
      end
    end

    context 'when the collection member itself is polymorphic' do
      let(:resource_class) { TaggableCollectionResource }
      let(:include) { 'tags' }

      it 'normalizes the nested includes once per type the collection serves' do
        expect(result).to eq({
          [:to_a, PostResource] => { [:tags, TagResource] => {} },
          [:to_a, CommentResource] => { [:tags, TagResource] => {} }
        })
      end
    end

    context 'with polymorphic includes' do
      let(:resource_class) { TagResource }
      let(:include) { 'taggables.tags' }

      specify do
        expect(result).to eq({
          [:taggables, CommentResource] => { [:tags, TagResource] => {} },
          [:taggables, PostResource] => { [:tags, TagResource] => {} }
        })
      end
    end

    context 'with polymorphic includes for specific type' do
      let(:resource_class) { TagResource }
      let(:include) { 'taggables:posts.tags' }

      specify do
        expect(result).to eq({
          [:taggables, CommentResource] => {},
          [:taggables, PostResource] => { [:tags, TagResource] => {} }
        })
      end
    end

    context 'with polymorphic includes for all types' do
      let(:resource_class) { TagResource }
      let(:include) { 'taggables:posts.post-author.comments,taggables:comments.comment-author.posts' }

      specify do
        expect(result).to eq({
          [:taggables, CommentResource] => {
            [:comment_author, UserResource] => {
              [:posts, PostCollectionResource] => { [:to_a, PostResource] => {} }
            }
          },
          [:taggables, PostResource] => {
            [:post_author, UserResource] => {
              [:comments, CommentCollectionResource] => { [:to_a, CommentResource] => {} }
            }
          }
        })
      end
    end

    context 'when invalid include is given' do
      let(:include) { 'post-author.Comments' }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid include `Comments` for `users`, valid includes are: `comments`, `posts`',
          status: 400,
          source: { parameter: 'include' }
        }))
      end
    end

    context 'when invalid type is given' do
      let(:resource_class) { TagResource }
      let(:include) { 'taggables:Posts.tags' }

      specify do
        expect { result }.to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid type `Posts` for include `taggables`, valid types are: `posts`, `comments`',
          status: 400,
          source: { parameter: 'include' }
        }))
      end
    end
  end
end
