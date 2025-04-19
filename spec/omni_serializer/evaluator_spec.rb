# frozen_string_literal: true

RSpec.describe OmniSerializer::Evaluator do
  subject(:evaluator) { described_class.new(loaders:) }

  let(:loaders) { {} }

  def traverse(value)
    case value
    when OmniSerializer::Evaluator::Placeholder
      traverse(value.values)
    when Array
      value.map { |item| traverse(item) }
    when Hash
      value.transform_values { |item| traverse(item) }
    else
      value
    end
  end

  describe '#call' do
    let(:query) { OmniSerializer::Query.new(name: :root, arguments: {}, schema: nil) }
    let(:context) { {} }

    it 'returns a primitive value' do
      expect(evaluator.call(42, query, context:)).to eq(42)
      expect(evaluator.call(%i[foo bar], query, context:)).to eq(%i[foo bar])
      expect(evaluator.call({ foo: 42 }, query, context:)).to eq({ foo: 42 })
    end

    context 'when the value is a resource' do
      let!(:post1) { Post.create!(title: 'Post 1', content: { foo: 42 }) }
      let!(:post2) { Post.create!(title: 'Post 2', content: ['foo', 42]) }

      before do
        stub_class(:post_resource, OmniSerializer::Resource) do
          attributes :title, :content
        end

        stub_class(:post_collection_resource, OmniSerializer::Resource) do
          collection resource: 'PostResource' do
            object
          end
        end
      end

      context 'when it is queried as primitive' do
        let(:query) { OmniSerializer::Query.new(name: :root, arguments: {}, schema: nil) }

        it 'returns the value' do
          expect(evaluator.call(post1, query, context:)).to eq(post1)
          expect(evaluator.call(Post.all.order(:name), query, context:)).to be_an(Array) & eq([post1, post2])
          expect(evaluator.call([post1, post2], query, context:)).to be_an(Array) & eq([post1, post2])
        end
      end

      context 'when it is queried as a resource' do
        let(:query) do
          OmniSerializer::Query.new(
            name: :root,
            arguments: {},
            schema: {
              resource: PostResource,
              members: [{
                name: :title,
                arguments: {},
                schema: nil
              }, {
                name: :content,
                arguments: {},
                schema: nil
              }]
            }
          )
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to eq({ title: 'Post 1', content: { 'foo' => 42 } })
          expect(traverse(evaluator.call(Post.all.order(:name), query, context:)))
            .to eq([{ title: 'Post 1', content: { 'foo' => 42 } }, { title: 'Post 2', content: ['foo', 42] }])
          expect(traverse(evaluator.call([post1, post2], query, context:)))
            .to eq([{ title: 'Post 1', content: { 'foo' => 42 } }, { title: 'Post 2', content: ['foo', 42] }])
        end
      end

      context 'when it is queried as a collection resource' do
        let(:query) do
          OmniSerializer::Query.new(
            name: :root,
            arguments: {},
            schema: {
              resource: PostCollectionResource,
              members: [{
                name: :to_a,
                arguments: {},
                schema: {
                  resource: PostResource,
                  members: [{
                    name: :title,
                    arguments: {},
                    schema: nil
                  }]
                }
              }]
            }
          )
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to be_nil
          expect(traverse(evaluator.call(Post.all.order(:name), query, context:)))
            .to eq(to_a: [{ title: 'Post 1' }, { title: 'Post 2' }])
          expect(traverse(evaluator.call([post1, post2], query, context:)))
            .to eq(to_a: [{ title: 'Post 1' }, { title: 'Post 2' }])
        end
      end

      context 'when the resource has associations' do
        let(:query) do
          OmniSerializer::Query.new(
            name: :root,
            arguments: {},
            schema: {
              resource: PostResource,
              members: [{
                name: :title,
                arguments: {},
                schema: nil
              }, {
                name: :comments,
                arguments: {},
                schema: {
                  resource: CommentCollectionResource,
                  members: [{
                    name: :to_a,
                    arguments: {},
                    schema: {
                      resource: CommentResource,
                      members: [{
                        name: :body,
                        arguments: {},
                        schema: nil
                      }]
                    }
                  }]
                }
              }, {
                name: :tags,
                arguments: {},
                schema: {
                  resource: TagResource,
                  members: [{
                    name: :name,
                    arguments: {},
                    schema: nil
                  }]
                }
              }, {
                name: :user,
                arguments: {},
                schema: {
                  resource: UserResource,
                  members: [{
                    name: :name,
                    arguments: {},
                    schema: nil
                  }]
                }
              }]
            }
          )
        end

        before do
          stub_class(:comment_resource, OmniSerializer::Resource) do
            attributes :body
          end

          stub_class(:comment_collection_resource, OmniSerializer::Resource) do
            collection resource: 'CommentResource'
          end

          stub_class(:tag_resource, OmniSerializer::Resource) do
            attribute :name
          end

          stub_class(:user_resource, OmniSerializer::Resource) do
            attribute :name
          end

          stub_class(:post_resource, OmniSerializer::Resource) do
            attributes :title
            has_one :user, resource: 'UserResource'
            has_many :comments, resource: 'CommentCollectionResource'
            has_many :tags, resource: 'TagResource'
          end

          User.create!(name: 'User 1', posts: [post1, post2])
          Comment.create!(post: post1, body: 'Comment 1')
          Comment.create!(post: post1, body: 'Comment 2')
          Comment.create!(post: post2, body: 'Comment 3')
          Tag.create!(name: 'Tag 1', posts: [post1, post2])
          Tag.create!(name: 'Tag 2', posts: [post1])
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to eq({
            title: 'Post 1',
            user: { name: 'User 1' },
            comments: { to_a: [{ body: 'Comment 1' }, { body: 'Comment 2' }] },
            tags: [{ name: 'Tag 1' }, { name: 'Tag 2' }]
          })
          expect(traverse(evaluator.call(Post.all.order(:name), query, context:))).to eq([{
            title: 'Post 1',
            user: { name: 'User 1' },
            comments: { to_a: [{ body: 'Comment 1' }, { body: 'Comment 2' }] },
            tags: [{ name: 'Tag 1' }, { name: 'Tag 2' }]
          }, {
            title: 'Post 2',
            user: { name: 'User 1' },
            comments: { to_a: [{ body: 'Comment 3' }] },
            tags: [{ name: 'Tag 1' }]
          }])
        end
      end
    end
  end
end
