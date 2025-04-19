# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi do
  subject(:serializer) { described_class.new(query_builder:, evaluator:, key_formatter:, type_formatter:) }

  let(:query_builder) { OmniSerializer::Jsonapi::QueryBuilder.new(key_formatter:, type_formatter:) }
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :snake } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :snake, number: :plural } }
  let(:evaluator) { OmniSerializer::Evaluator.new(loaders:) }
  let(:loaders) { {} }

  describe '#serialize' do
    let!(:post1) { Post.create!(title: 'Post 1', content: { foo: 42 }) }
    let!(:post2) { Post.create!(title: 'Post 2', content: ['foo', 42]) }
    let!(:post3) { Post.create!(title: 'Post 3') }
    let!(:comment1) { Comment.create!(post: post1, body: 'Comment 1') }
    let!(:comment2) { Comment.create!(post: post1, body: 'Comment 2') }
    let!(:comment3) { Comment.create!(post: post2, body: 'Comment 3') }
    let!(:user1) { User.create!(name: 'User 1', posts: [post1, post2]) }

    specify do
      expect(serializer.serialize(post1, with: PostResource)).to eq({ data: {
        id: post1.id.to_s,
        type: 'posts',
        attributes: { 'post_title' => 'Post 1', 'post_content' => { 'foo' => 42 } },
        relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
      } })
      expect(serializer.serialize(
        [post1, post2],
        with: PostResource,
        params: { include: 'post_author,comments' }
      )).to eq({
        data: [{
          id: post1.id.to_s,
          type: 'posts',
          attributes: { 'post_title' => 'Post 1', 'post_content' => { 'foo' => 42 } },
          relationships: {
            'post_author' => { data: { id: user1.id.to_s, type: 'users' } },
            'comments' => { data: [
              { id: comment1.id.to_s, type: 'comments' },
              { id: comment2.id.to_s, type: 'comments' }
            ] },
            'taggings' => {},
            'tags' => {}
          }
        }, {
          id: post2.id.to_s,
          type: 'posts',
          attributes: { 'post_title' => 'Post 2', 'post_content' => ['foo', 42] },
          relationships: {
            'post_author' => { data: { id: user1.id.to_s, type: 'users' } },
            'comments' => { data: [{ id: comment3.id.to_s, type: 'comments' }] },
            'taggings' => {},
            'tags' => {}
          }
        }],
        included: [{
          id: user1.id.to_s,
          type: 'users',
          attributes: { 'user_name' => 'User 1' },
          relationships: { 'comments' => {}, 'posts' => {} }
        }, {
          id: comment1.id.to_s,
          type: 'comments',
          attributes: { 'comment_body' => 'Comment 1' },
          relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: comment2.id.to_s,
          type: 'comments',
          attributes: { 'comment_body' => 'Comment 2' },
          relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: comment3.id.to_s,
          type: 'comments',
          attributes: { 'comment_body' => 'Comment 3' },
          relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
        }]
      })
      expect(serializer.serialize(Post.all.order(:title), with: PostResource,
        params: { fields: { posts: 'post_title' } })).to eq({ data: [{
          id: post1.id.to_s,
          type: 'posts',
          attributes: { 'post_title' => 'Post 1' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: post2.id.to_s,
          type: 'posts',
          attributes: { 'post_title' => 'Post 2' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }, {
          id: post3.id.to_s,
          type: 'posts',
          attributes: { 'post_title' => 'Post 3' },
          relationships: { 'post_author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
        }] })
    end

    specify do
      expect(serializer.serialize([comment1, comment2], with: CommentCollectionResource)).to eq({ data: [{
        id: comment1.id.to_s,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 1' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment2.id.to_s,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 2' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }] })
      expect(serializer.serialize(Comment.all.order(:body), with: CommentCollectionResource)).to eq({ data: [{
        id: comment1.id.to_s,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 1' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment2.id.to_s,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 2' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }, {
        id: comment3.id.to_s,
        type: 'comments',
        attributes: { 'comment_body' => 'Comment 3' },
        relationships: { 'comment_author' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
      }] })
    end

    context 'with recursive includes' do
      let(:key_formatter_options) { { casing: :kebab } }
      let(:type_formatter_options) { { casing: :pascal, number: :plural } }

      let!(:category1) { Category.create!(name: 'Category 1', parent: nil) }
      let!(:category2) { Category.create!(name: 'Category 2', parent: nil) }
      let!(:category3) { Category.create!(name: 'Category 3', parent: category1) }
      let!(:category4) { Category.create!(name: 'Category 4', parent: category2) }
      let!(:category5) { Category.create!(name: 'Category 5', parent: category2) }
      let!(:category6) { Category.create!(name: 'Category 6', parent: category3) }

      before do
        post1.update!(category: category1)
        post2.update!(category: category3)
        post3.update!(category: category5)
      end

      specify do
        expect(serializer.serialize(
          Category.where(parent_id: nil),
          with: CategoryResource,
          params: { include: 'parent,children,posts' }
        )).to eq({
          data: [{
            id: category1.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 1' },
            relationships: {
              'parent' => { data: nil },
              'children' => { data: [{ id: category3.id.to_s, type: 'Categories' }] },
              'posts' => { data: [{ id: post1.id.to_s, type: 'Posts' }] }
            }
          }, {
            id: category2.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 2' },
            relationships: {
              'parent' => { data: nil },
              'children' => { data: [
                { id: category4.id.to_s, type: 'Categories' },
                { id: category5.id.to_s, type: 'Categories' }
              ] },
              'posts' => { data: [] }
            }
          }],
          included: [{
            id: category3.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 3' },
            relationships: {
              'parent' => { data: { id: category1.id.to_s, type: 'Categories' } },
              'children' => { data: [{ id: category6.id.to_s, type: 'Categories' }] },
              'posts' => { data: [{ id: post2.id.to_s, type: 'Posts' }] }
            }
          }, {
            id: category4.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 4' },
            relationships: {
              'parent' => { data: { id: category2.id.to_s, type: 'Categories' } },
              'children' => { data: [] },
              'posts' => { data: [] }
            }
          }, {
            id: category5.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 5' },
            relationships: {
              'parent' => { data: { id: category2.id.to_s, type: 'Categories' } },
              'children' => { data: [] },
              'posts' => { data: [{ id: post3.id.to_s, type: 'Posts' }] }
            }
          }, {
            id: category6.id.to_s,
            type: 'Categories',
            attributes: { 'category-name' => 'Category 6' },
            relationships: {
              'parent' => {},
              'children' => {},
              'posts' => {}
            }
          }, {
            id: post1.id.to_s,
            type: 'Posts',
            attributes: { 'post-title' => 'Post 1', 'post-content' => { 'foo' => 42 } },
            relationships: { 'post-author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
          }, {
            id: post2.id.to_s,
            type: 'Posts',
            attributes: { 'post-title' => 'Post 2', 'post-content' => ['foo', 42] },
            relationships: { 'post-author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
          }, {
            id: post3.id.to_s,
            type: 'Posts',
            attributes: { 'post-title' => 'Post 3', 'post-content' => nil },
            relationships: { 'post-author' => {}, 'comments' => {}, 'taggings' => {}, 'tags' => {} }
          }]
        })
      end
    end

    context 'with polymorphic association' do
      let(:key_formatter_options) { { casing: :camel } }
      let(:type_formatter_options) { { casing: :camel, number: :singular } }

      let!(:tag1) { Tag.create!(name: 'Tag 1', posts: [post1, post2]) }
      let!(:tag2) { Tag.create!(name: 'Tag 2', posts: [post1], comments: [comment1, comment2]) }

      specify do
        expect(serializer.serialize(Tagging.order(:id),
          with: TaggingResource,
          params: {
            include: 'tag,taggable:post.postAuthor',
            fields: { post: 'postTitle', comment: 'commentBody' }
          })).to match({
            data: [{
              id: an_instance_of(String),
              type: 'tagging',
              attributes: {},
              relationships: {
                'tag' => { data: { id: tag1.id.to_s, type: 'tag' } },
                'taggable' => { data: { id: post1.id.to_s, type: 'post' } }
              }
            }, {
              id: an_instance_of(String),
              type: 'tagging',
              attributes: {},
              relationships: {
                'tag' => { data: { id: tag1.id.to_s, type: 'tag' } },
                'taggable' => { data: { id: post2.id.to_s, type: 'post' } }
              }
            }, {
              id: an_instance_of(String),
              type: 'tagging',
              attributes: {},
              relationships: {
                'tag' => { data: { id: tag2.id.to_s, type: 'tag' } },
                'taggable' => { data: { id: post1.id.to_s, type: 'post' } }
              }
            }, {
              id: an_instance_of(String),
              type: 'tagging',
              attributes: {},
              relationships: {
                'tag' => { data: { id: tag2.id.to_s, type: 'tag' } },
                'taggable' => { data: { id: comment1.id.to_s, type: 'comment' } }
              }
            }, {
              id: an_instance_of(String),
              type: 'tagging',
              attributes: {},
              relationships: {
                'tag' => { data: { id: tag2.id.to_s, type: 'tag' } },
                'taggable' => { data: { id: comment2.id.to_s, type: 'comment' } }
              }
            }],
            included: [{
              id: tag1.id.to_s,
              type: 'tag',
              attributes: { 'tagName' => 'Tag 1' },
              relationships: { 'tagging' => {}, 'taggables' => {} }
            }, {
              id: post1.id.to_s,
              type: 'post',
              attributes: { 'postTitle' => 'Post 1' },
              relationships: {
                'postAuthor' => { data: { id: user1.id.to_s, type: 'user' } },
                'comments' => {},
                'taggings' => {},
                'tags' => {}
              }
            }, {
              id: post2.id.to_s,
              type: 'post',
              attributes: { 'postTitle' => 'Post 2' },
              relationships: {
                'postAuthor' => { data: { id: user1.id.to_s, type: 'user' } },
                'comments' => {},
                'taggings' => {},
                'tags' => {}
              }
            }, {
              id: tag2.id.to_s,
              type: 'tag',
              attributes: { 'tagName' => 'Tag 2' },
              relationships: { 'tagging' => {}, 'taggables' => {} }
            }, {
              id: comment1.id.to_s,
              type: 'comment',
              attributes: { 'commentBody' => 'Comment 1' },
              relationships: { 'commentAuthor' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
            }, {
              id: comment2.id.to_s,
              type: 'comment',
              attributes: { 'commentBody' => 'Comment 2' },
              relationships: { 'commentAuthor' => {}, 'post' => {}, 'taggings' => {}, 'tags' => {} }
            }, {
              id: user1.id.to_s,
              type: 'user',
              attributes: { 'userName' => 'User 1' },
              relationships: { 'comments' => {}, 'posts' => {} }
            }]
          })
      end
    end
  end
end
