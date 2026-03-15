# frozen_string_literal: true

RSpec.describe OmniSerializer::Simple do
  subject(:serializer) { described_class.build(loaders:, key_formatter:, **options) }

  let(:loaders) { { record: RecordLoader, collection: CollectionLoader, aggregate: AggregateLoader } }
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { {} }
  let(:options) { {} }

  describe '#serialize' do
    let!(:post1) { Post.create!(title: 'Post 1', content: { foo: 42 }, published_at: 1.day.ago) }
    let!(:post2) { Post.create!(title: 'Post 2', content: ['foo', 42], published_at: 1.day.ago) }
    let!(:post3) { Post.create!(title: 'Post 3') }
    let!(:comment1) { Comment.create!(post: post1, body: 'Comment 1') }
    let!(:comment2) { Comment.create!(post: post1, body: 'Comment 2') }
    let!(:comment3) { Comment.create!(post: post2, body: 'Comment 3') }
    let!(:user1) { User.create!(name: 'User 1', posts: [post1, post2]) }
    let!(:tag1) { Tag.create!(name: 'Tag 1', posts: [post1, post2, post3]) }
    let!(:tag2) { Tag.create!(name: 'Tag 2', posts: [post1], comments: [comment1, comment2]) }

    specify do
      expect(serializer.serialize(post1, with: PostResource, params: {
        only: :post_title, except: :invalid, extra: nil
      })).to eq({ 'post_title' => 'Post 1' })
      expect(serializer.serialize([post1, post2], with: PostResource, params: {
        only: nil, except: :post_title, extra: :invalid, include: nil
      })).to eq([
        { 'id' => post1.id, 'post_content' => { 'foo' => 42 } },
        { 'id' => post2.id, 'post_content' => ['foo', 42] }
      ])
      expect(serializer.serialize(Post.all.order(:title), with: PostResource, params: {
        only: [:post_title], except: nil, extra: :tag_names, include: %i[post_author active_comments]
      })).to eq([
        {
          'post_title' => 'Post 1',
          'tag_names' => ['Tag 1', 'Tag 2'],
          'post_author' => { 'id' => user1.id, 'user_name' => 'User 1' },
          'active_comments' => {
            'pagination' => { 'current_page' => 1, 'total_count' => 2, 'total_pages' => 1 },
            'collection' => [
              { 'id' => comment1.id, 'comment_body' => 'Comment 1' },
              { 'id' => comment2.id, 'comment_body' => 'Comment 2' }
            ]
          }
        },
        {
          'post_title' => 'Post 2',
          'tag_names' => ['Tag 1'],
          'post_author' => { 'id' => user1.id, 'user_name' => 'User 1' },
          'active_comments' => {
            'pagination' => { 'current_page' => 1, 'total_count' => 1, 'total_pages' => 1 },
            'collection' => [{ 'id' => comment3.id, 'comment_body' => 'Comment 3' }]
          }
        },
        {
          'post_title' => 'Post 3',
          'tag_names' => ['Tag 1'],
          'post_author' => nil,
          'active_comments' => {
            'pagination' => { 'current_page' => 1, 'total_count' => 0, 'total_pages' => 0 },
            'collection' => []
          }
        }
      ])
    end

    context 'when params include runtime arguments' do
      before { Comment.create!(post: post1, body: 'Deleted comment', deleted_at: 1.day.ago) }

      specify do
        expect(serializer.serialize(Comment.all.order(:body), with: CommentCollectionResource, params: {
          'page' => { 'number' => 2, 'size' => 1 },
          'filter' => { 'active' => true },
          'only' => 'comment_body'
        })).to eq({
          'pagination' => { 'current_page' => 2, 'total_count' => 3, 'total_pages' => 3 },
          'collection' => [{ 'comment_body' => 'Comment 2' }]
        })
      end
    end

    context 'with nested collection wrapper options' do
      specify do
        expect(serializer.serialize(post1, with: PostResource, params: {
          'include' => {
            'active_comments' => {
              'only' => 'comment_body',
              'collection' => { 'only' => 'current_page' }
            }
          }
        })).to eq({
          'id' => post1.id,
          'post_title' => 'Post 1',
          'post_content' => { 'foo' => 42 },
          'active_comments' => {
            'current_page' => 1,
            'collection' => [
              { 'comment_body' => 'Comment 1' },
              { 'comment_body' => 'Comment 2' }
            ]
          }
        })
      end
    end

    context 'with collection serializer defined' do
      let(:key_formatter_options) { { casing: :camel } }
      let(:options) { { collection_key: :my_collection } }

      specify do
        expect(serializer.serialize(comment1, with: CommentResource, params: {
          only: [],
          include: { post: { only: :post_title } }
        })).to eq({ 'post' => { 'postTitle' => 'Post 1' } })
        expect(serializer.serialize(Comment.where(id: [comment1, comment2]), with: CommentCollectionResource, params: {
          include: { post: { only: :post_title, include: :post_author } }
        })).to eq({
          'pagination' => { 'currentPage' => 1, 'totalCount' => 2, 'totalPages' => 1 },
          'myCollection' => [
            { 'id' => comment1.id, 'commentBody' => 'Comment 1',
              'post' => { 'postTitle' => 'Post 1', 'postAuthor' => { 'id' => user1.id, 'userName' => 'User 1' } } },
            { 'id' => comment2.id, 'commentBody' => 'Comment 2',
              'post' => { 'postTitle' => 'Post 1', 'postAuthor' => { 'id' => user1.id, 'userName' => 'User 1' } } }
          ]
        })
        expect(serializer.serialize(Comment.all.order(:body), with: CommentCollectionResource, params: {
          collection: { only: [] }, only: [], extra: [:comment_body]
        })).to eq([
          { 'commentBody' => 'Comment 1' },
          { 'commentBody' => 'Comment 2' },
          { 'commentBody' => 'Comment 3' }
        ])
      end
    end

    context 'with polymorphic association' do
      let(:key_formatter_options) { { casing: :kebab } }

      specify do
        expect(serializer.serialize(Tagging.all, with: TaggingResource, context: { now: Time.now.utc }, params: {
          include: [:tag, { taggable: { only: %i[post_title comment_body] } }], only: []
        })).to eq([
          { 'tag' => { 'id' => tag1.id, 'tag-name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 1' } },
          { 'tag' => { 'id' => tag1.id, 'tag-name' => 'Tag 1' }, 'taggable' => { 'post-title' => 'Post 2' } },
          { 'tag' => { 'id' => tag1.id, 'tag-name' => 'Tag 1' }, 'taggable' => nil },
          { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'post-title' => 'Post 1' } },
          { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 1' } },
          { 'tag' => { 'id' => tag2.id, 'tag-name' => 'Tag 2' }, 'taggable' => { 'comment-body' => 'Comment 2' } }
        ])
      end
    end

    context 'with root: true' do
      let(:options) { { root: true } }
      let(:key_formatter_options) { { casing: :pascal } }

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
