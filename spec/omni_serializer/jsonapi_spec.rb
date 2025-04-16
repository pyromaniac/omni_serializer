# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi do
  subject(:serializer) { described_class.new(query_builder:, evaluator:, inflector:, **options) }

  let(:query_builder) { OmniSerializer::Jsonapi::QueryBuilder.new(inflector:) }
  let(:evaluator) { OmniSerializer::Evaluator.new(loaders:) }
  let(:inflector) { Dry::Inflector.new }
  let(:loaders) { {} }
  let(:options) { {} }

  describe '#serialize' do
    let!(:post1) { Post.create!(title: 'Post 1', content: { foo: 42 }) }
    let!(:post2) { Post.create!(title: 'Post 2', content: ['foo', 42]) }
    let!(:post3) { Post.create!(title: 'Post 3') }
    let!(:comment1) { Comment.create!(post: post1, body: 'Comment 1') }
    let!(:comment2) { Comment.create!(post: post1, body: 'Comment 2') }
    let!(:comment3) { Comment.create!(post: post2, body: 'Comment 3') }
    let!(:user1) { User.create!(name: 'User 1', posts: [post1, post2]) }
    let!(:tag1) { Tag.create!(name: 'Tag 1', posts: [post1, post2]) }
    let!(:tag2) { Tag.create!(name: 'Tag 2', posts: [post1], comments: [comment1, comment2]) }

    specify do
      expect(serializer.serialize(post1, with: PostResource)).to eq({ data: {
        id: post1.id,
        type: 'posts',
        attributes: { 'post_title' => 'Post 1', 'post_content' => { 'foo' => 42 } },
        relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
      } })
      expect(serializer.serialize([post1, post2], with: PostResource,
        params: { include: 'post_author,comments' })).to eq({
          data: [{
            id: post1.id,
            type: 'posts',
            attributes: { 'post_title' => 'Post 1', 'post_content' => { 'foo' => 42 } },
            relationships: {
              'post_author' => { data: { id: user1.id, type: 'users' } },
              'comments' => { data: [{ id: comment1.id, type: 'comments' }, { id: comment2.id, type: 'comments' }] },
              'taggings' => {},
              'tags' => {}
            }
          }, {
            id: post2.id,
            type: 'posts',
            attributes: { 'post_title' => 'Post 2', 'post_content' => ['foo', 42] },
            relationships: {
              'post_author' => { data: { id: user1.id, type: 'users' } },
              'comments' => { data: [{ id: comment3.id, type: 'comments' }] },
              'taggings' => {},
              'tags' => {}
            }
          }],
          included: [{
            id: user1.id,
            type: 'users',
            attributes: { 'user_name' => 'User 1' },
            relationships: { 'comments' => {}, 'posts' => {} }
          }, {
            id: comment1.id,
            type: 'comments',
            attributes: { 'comment_body' => 'Comment 1' },
            relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
          }, {
            id: comment2.id,
            type: 'comments',
            attributes: { 'comment_body' => 'Comment 2' },
            relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
          }, {
            id: comment3.id,
            type: 'comments',
            attributes: { 'comment_body' => 'Comment 3' },
            relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
          }]
        })
      expect(serializer.serialize(Post.all.order(:title), with: PostResource,
        params: { fields: { posts: 'post_title' } })).to eq({ data: [{
          id: post1.id,
          type: 'posts',
          attributes: { 'post_title' => 'Post 1' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: post2.id,
          type: 'posts',
          attributes: { 'post_title' => 'Post 2' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: post3.id,
          type: 'posts',
          attributes: { 'post_title' => 'Post 3' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }] })
    end

    specify do
      expect(serializer.serialize([comment1, comment2], with: CommentCollectionResource)).to eq({ data: [{
        id: comment1.id,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 1' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment2.id,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 2' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }] })
      expect(serializer.serialize(Comment.all.order(:body), with: CommentCollectionResource)).to eq({ data: [{
        id: comment1.id,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 1' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment2.id,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 2' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment3.id,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 3' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }] })
    end

    # context 'with polymorphic association' do
    #   let(:options) { { key_transform: :dash } }

    #   specify do
    #     expect(serializer.serialize(Tagging.all, with: TaggingResource,
    #       include: [:tag, { taggable: { only: %i[post_title comment_body] } }])).to eq([
    #         { 'tag' => { 'name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 1' } },
    #         { 'tag' => { 'name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 2' } },
    #         { 'tag' => { 'name' => 'Tag 2' }, 'taggable' => { 'post-title' => 'Post 1' } },
    #         { 'tag' => { 'name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 1' } },
    #         { 'tag' => { 'name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 2' } }
    #       ])
    #   end
    # end
  end
end
