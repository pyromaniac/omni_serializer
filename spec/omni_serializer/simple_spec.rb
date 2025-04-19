# frozen_string_literal: true

RSpec.describe OmniSerializer::Simple do
  subject(:serializer) { described_class.new(query_builder:, evaluator:, inflector:, **options) }

  let(:query_builder) { OmniSerializer::Simple::QueryBuilder.new }
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
      expect(serializer.serialize(post1, with: PostResource,
        only: :post_title, except: :invalid, extra: nil)).to eq({ 'post_title' => 'Post 1' })
      expect(serializer.serialize([post1, post2], with: PostResource,
        only: nil, except: :post_title, extra: :invalid, include: nil)).to eq([
          { 'id' => post1.id, 'post_content' => { 'foo' => 42 } },
          { 'id' => post2.id, 'post_content' => ['foo', 42] }
        ])
      expect(serializer.serialize(Post.all.order(:title), with: PostResource,
        only: [:post_title], except: nil, extra: :comments_count, include: %i[post_author comments])).to eq([
          {
            'post_title' => 'Post 1',
            'comments_count' => 2,
            'post_author' => { 'id' => user1.id, 'user_name' => 'User 1' },
            'comments' => [
              { 'id' => comment1.id, 'comment_body' => 'Comment 1' },
              { 'id' => comment2.id, 'comment_body' => 'Comment 2' }
            ]
          },
          {
            'post_title' => 'Post 2',
            'comments_count' => 1,
            'post_author' => { 'id' => user1.id, 'user_name' => 'User 1' },
            'comments' => [{ 'id' => comment3.id, 'comment_body' => 'Comment 3' }]
          },
          { 'post_title' => 'Post 3', 'comments_count' => 0, 'post_author' => nil, 'comments' => [] }
        ])
    end

    context 'with collection serializer defined' do
      let(:options) { { key_transform: :camel_lower } }

      specify do
        expect(serializer.serialize(comment1, with: CommentResource, only: [],
          include: { post: { only: :post_title } }))
          .to eq({ 'post' => { 'postTitle' => 'Post 1' } })
        expect(serializer.serialize([comment1, comment2], with: CommentCollectionResource,
          include: { post: { only: :post_title, include: :post_author } })).to eq([
            { 'id' => comment1.id, 'commentBody' => 'Comment 1',
              'post' => { 'postTitle' => 'Post 1', 'postAuthor' => { 'id' => user1.id, 'userName' => 'User 1' } } },
            { 'id' => comment2.id, 'commentBody' => 'Comment 2',
              'post' => { 'postTitle' => 'Post 1', 'postAuthor' => { 'id' => user1.id, 'userName' => 'User 1' } } }
          ])
        expect(serializer.serialize(Comment.all.order(:body), with: CommentCollectionResource, only: [],
          extra: [:comment_body])).to eq([
            { 'commentBody' => 'Comment 1' },
            { 'commentBody' => 'Comment 2' },
            { 'commentBody' => 'Comment 3' }
          ])
      end
    end

    context 'with polymorphic association' do
      let(:options) { { key_transform: :dash } }

      specify do
        expect(serializer.serialize(Tagging.all, with: TaggingResource,
          include: [:tag, { taggable: { only: %i[post_title comment_body] } }], only: [])).to eq([
            { 'tag' => { 'id' => tag1.id, 'tag-name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 1' } },
            { 'tag' => { 'id' => tag1.id, 'tag-name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 2' } },
            { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'post-title' => 'Post 1' } },
            { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 1' } },
            { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 2' } }
          ])
      end
    end

    context 'with root: true' do
      let(:options) { { root: true, key_transform: :camel } }

      specify do
        expect(serializer.serialize(post1, with: PostResource))
          .to eq({ 'Post' => { 'Id' => post1.id, 'PostTitle' => 'Post 1', 'PostContent' => { 'foo' => 42 } } })
        expect(serializer.serialize([post1, post2], with: PostResource)).to eq({ 'Posts' => [
          { 'Id' => post1.id, 'PostTitle' => 'Post 1', 'PostContent' => { 'foo' => 42 } },
          { 'Id' => post2.id, 'PostTitle' => 'Post 2', 'PostContent' => ['foo', 42] }
        ] })
      end
    end
  end
end
