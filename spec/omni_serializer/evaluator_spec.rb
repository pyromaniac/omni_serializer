# frozen_string_literal: true

RSpec.describe OmniSerializer::Evaluator do
  subject(:evaluator) { described_class.new(loaders:) }

  let(:loaders) { { record: RecordLoader, collection: CollectionLoader, aggregate: AggregateLoader } }

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
    let(:query) { OmniSerializer::Query.build(:root) }
    let(:context) { {} }

    it 'returns a primitive value' do
      expect(evaluator.call(42, query, context:)).to eq(42)
      expect(evaluator.call(%i[foo bar], query, context:)).to eq(%i[foo bar])
      expect(evaluator.call({ foo: 42 }, query, context:)).to eq({ foo: 42 })
    end

    context 'when the value is a resource' do
      let(:category1) { Category.create!(name: 'Category 1') }
      let(:category2) { Category.create!(name: 'Category 2', parent: category1) }
      let(:category3) { Category.create!(name: 'Category 3', parent: category1) }
      let(:post1) { Post.create!(title: 'Post 1', content: { foo: 42 }, published_at: 1.day.ago, category: category1) }
      let(:post2) { Post.create!(title: 'Post 2', content: ['foo', 42], published_at: 1.day.ago, category: category1) }
      let(:post3) { Post.create!(title: 'Post 3', content: 'foo', published_at: 1.day.ago, category: category3) }
      let(:post4) { Post.create!(title: 'Post 4', category: category2) }
      let(:comment1) { Comment.create!(post: post1, body: 'Comment 1') }
      let(:comment2) { Comment.create!(post: post1, body: 'Comment 2') }
      let(:comment3) { Comment.create!(post: post2, body: 'Comment 3') }
      let!(:tag1) { Tag.create!(name: 'Tag 1', posts: [post1, post2, post3], comments: [comment1, comment2]) }
      let!(:tag2) { Tag.create!(name: 'Tag 2', comments: [comment2, comment3]) }

      before do
        Category.create!(name: 'Category 4', parent: category2)
        Tag.create!(name: 'Tag 3', posts: [post2, post3, post4])
        User.create!(name: 'User 1', posts: [post1, post2], comments: [comment1])
        User.create!(name: 'User 2', posts: [post3, post4])
        User.create!(name: 'User 3', comments: [comment2, comment3])
      end

      context 'when it is queried as primitive' do
        it 'returns the value' do
          expect(evaluator.call(post1, query, context:)).to eq(post1)
          expect(evaluator.call(Post.all.order(:title), query, context:))
            .to be_an(Array) & eq([post1, post2, post3, post4])
          expect(evaluator.call([post1, post2], query, context:)).to be_an(Array) & eq([post1, post2])
        end
      end

      context 'when it is queried as a resource' do
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: PostResource,
            members: [OmniSerializer::Query.build(:post_title), OmniSerializer::Query.build(:post_content)]
          })
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:)))
            .to eq({ post_title: 'Post 1', post_content: { 'foo' => 42 } })
          expect(traverse(evaluator.call(Post.all.order(:title), query, context:))).to eq([
            { post_title: 'Post 1', post_content: { 'foo' => 42 } },
            { post_title: 'Post 2', post_content: ['foo', 42] },
            { post_title: 'Post 3', post_content: 'foo' },
            { post_title: 'Post 4', post_content: nil }
          ])
          expect(traverse(evaluator.call([post1, post2], query, context:))).to eq([
            { post_title: 'Post 1', post_content: { 'foo' => 42 } },
            { post_title: 'Post 2', post_content: ['foo', 42] }
          ])
        end
      end

      context 'when it is queried as a collection resource' do
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: PostCollectionResource,
            members: [OmniSerializer::Query.build(:to_a, schema: {
              resource: PostResource,
              members: [OmniSerializer::Query.build(:post_title)]
            })]
          })
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to be_nil
          expect(traverse(evaluator.call(Post.all.order(:title), query, context:))).to eq(to_a: [
            { post_title: 'Post 1' }, { post_title: 'Post 2' },
            { post_title: 'Post 3' }, { post_title: 'Post 4' }
          ])
          expect(traverse(evaluator.call([post1, post2], query, context:)))
            .to eq(to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }])
        end
      end

      context 'when the resource has associations' do
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: PostResource,
            members: [
              OmniSerializer::Query.build(:post_title),
              OmniSerializer::Query.build(:tag_names),
              OmniSerializer::Query.build(:post_author, schema: {
                resource: UserResource,
                members: [OmniSerializer::Query.build(:user_name)]
              }),
              OmniSerializer::Query.build(:active_comments, schema: {
                resource: CommentCollectionResource,
                members: [
                  OmniSerializer::Query.build(:to_a, schema: {
                    resource: CommentResource,
                    members: [OmniSerializer::Query.build(:comment_body)]
                  }),
                  OmniSerializer::Query.build(:pagination)
                ]
              }),
              OmniSerializer::Query.build(:taggings, schema: { resource: TaggingResource, members: [] }),
              OmniSerializer::Query.build(:tags, schema: {
                resource: TagResource,
                members: [OmniSerializer::Query.build(:tag_name)]
              })
            ]
          })
        end

        it 'utilizes loaders' do
          expect { traverse(evaluator.call(post1, query, context:)) }
            .to make_database_queries(count: 5)
          expect { traverse(evaluator.call([post1, post2], query, context:)) }
            .to make_database_queries(count: 5)
          expect { traverse(evaluator.call(Post.all.order(:title), query, context:)) }
            .to make_database_queries(count: 6)
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to eq({
            post_title: 'Post 1',
            tag_names: ['Tag 1'],
            post_author: { user_name: 'User 1' },
            active_comments: {
              to_a: [{ comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            },
            taggings: [{}],
            tags: [{ tag_name: 'Tag 1' }]
          })
          expect(traverse(evaluator.call(Post.all.order(:title), query, context:))).to eq([{
            post_title: 'Post 1',
            post_author: { user_name: 'User 1' },
            tag_names: ['Tag 1'],
            active_comments: {
              to_a: [{ comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            },
            taggings: [{}],
            tags: [{ tag_name: 'Tag 1' }]
          }, {
            post_title: 'Post 2',
            post_author: { user_name: 'User 1' },
            tag_names: ['Tag 1', 'Tag 3'],
            active_comments: {
              to_a: [{ comment_body: 'Comment 3' }],
              pagination: { total_count: 1, total_pages: 1, current_page: 1 }
            },
            taggings: [{}, {}],
            tags: [{ tag_name: 'Tag 1' }, { tag_name: 'Tag 3' }]
          }, {
            post_title: 'Post 3',
            post_author: { user_name: 'User 2' },
            tag_names: ['Tag 1', 'Tag 3'],
            active_comments: {
              to_a: [],
              pagination: { total_count: 0, total_pages: 0, current_page: 1 }
            },
            taggings: [{}, {}],
            tags: [{ tag_name: 'Tag 1' }, { tag_name: 'Tag 3' }]
          }, {
            post_title: 'Post 4',
            post_author: { user_name: 'User 2' },
            tag_names: ['Tag 3'],
            active_comments: {
              to_a: [],
              pagination: { total_count: 0, total_pages: 0, current_page: 1 }
            },
            taggings: [{}],
            tags: [{ tag_name: 'Tag 3' }]
          }])
        end
      end

      context 'when multiple levels queried' do
        let(:context) { { now: Time.now.utc } }
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: PostResource,
            members: [
              OmniSerializer::Query.build(:post_title),
              OmniSerializer::Query.build(:post_author, schema: {
                resource: UserResource,
                members: [
                  OmniSerializer::Query.build(:user_name),
                  OmniSerializer::Query.build(:comments, schema: {
                    resource: CommentCollectionResource,
                    members: [
                      OmniSerializer::Query.build(:pagination),
                      OmniSerializer::Query.build(:to_a, schema: {
                        resource: CommentResource,
                        members: [OmniSerializer::Query.build(:comment_body)]
                      })
                    ]
                  }),
                  OmniSerializer::Query.build(:posts, schema: {
                    resource: PostCollectionResource,
                    members: [
                      OmniSerializer::Query.build(:pagination),
                      OmniSerializer::Query.build(:to_a, schema: {
                        resource: PostResource,
                        members: [OmniSerializer::Query.build(:post_title)]
                      })
                    ]
                  })
                ]
              }),
              OmniSerializer::Query.build(:active_comments, schema: {
                resource: CommentCollectionResource,
                members: [
                  OmniSerializer::Query.build(:pagination),
                  OmniSerializer::Query.build(:to_a, schema: {
                    resource: CommentResource,
                    members: [OmniSerializer::Query.build(:comment_body)]
                  })
                ]
              })
            ]
          })
        end

        it 'utilizes loaders' do
          expect { traverse(evaluator.call(post1, query, context:)) }
            .to make_database_queries(count: 7)
          expect { traverse(evaluator.call([post1, post2], query, context:)) }
            .to make_database_queries(count: 7)
          expect { traverse(evaluator.call(Post.all.order(:title), query, context:)) }
            .to make_database_queries(count: 8)
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(post1, query, context:))).to eq({
            post_title: 'Post 1',
            post_author: {
              user_name: 'User 1',
              comments: {
                to_a: [{ comment_body: 'Comment 1' }],
                pagination: { total_count: 1, total_pages: 1, current_page: 1 }
              },
              posts: {
                to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }],
                pagination: { total_count: 2, total_pages: 1, current_page: 1 }
              }
            },
            active_comments: {
              to_a: [{ comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            }
          })
          expect(traverse(evaluator.call([post1, post2], query, context:))).to eq([{
            post_title: 'Post 1',
            post_author: {
              user_name: 'User 1',
              comments: {
                to_a: [{ comment_body: 'Comment 1' }],
                pagination: { total_count: 1, total_pages: 1, current_page: 1 }
              },
              posts: {
                to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }],
                pagination: { total_count: 2, total_pages: 1, current_page: 1 }
              }
            },
            active_comments: {
              to_a: [{ comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            }
          }, {
            post_title: 'Post 2',
            post_author: {
              user_name: 'User 1',
              comments: {
                to_a: [{ comment_body: 'Comment 1' }],
                pagination: { total_count: 1, total_pages: 1, current_page: 1 }
              },
              posts: {
                to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }],
                pagination: { total_count: 2, total_pages: 1, current_page: 1 }
              }
            },
            active_comments: {
              to_a: [{ comment_body: 'Comment 3' }],
              pagination: { total_count: 1, total_pages: 1, current_page: 1 }
            }
          }])
        end
      end

      context 'with polymorphic association queried' do
        let(:context) { { now: Time.now.utc } }
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: TagResource,
            members: [
              OmniSerializer::Query.build(:tag_name),
              OmniSerializer::Query.build(:taggings, schema: {
                resource: TaggingResource,
                members: [
                  OmniSerializer::Query.build(:taggable, schema: {
                    Post => {
                      resource: PostResource,
                      members: [OmniSerializer::Query.build(:post_title)]
                    },
                    Comment => {
                      resource: CommentResource,
                      members: [OmniSerializer::Query.build(:comment_body)]
                    }
                  })
                ]
              }),
              OmniSerializer::Query.build(:taggables, schema: {
                Post => {
                  resource: PostResource,
                  members: [
                    OmniSerializer::Query.build(:post_title),
                    OmniSerializer::Query.build(:tags, schema: {
                      resource: TagResource,
                      members: [
                        OmniSerializer::Query.build(:tag_name),
                        OmniSerializer::Query.build(:taggables, schema: {
                          Post => {
                            resource: PostResource,
                            members: [OmniSerializer::Query.build(:post_title)]
                          },
                          Comment => {
                            resource: CommentResource,
                            members: [OmniSerializer::Query.build(:comment_body)]
                          }
                        })
                      ]
                    })
                  ]
                },
                Comment => {
                  resource: CommentResource,
                  members: [OmniSerializer::Query.build(:comment_body)]
                }
              })
            ]
          })
        end

        it 'utilizes loaders' do
          expect { traverse(evaluator.call(tag1, query, context:)) }
            .to make_database_queries(count: 8)
          expect { traverse(evaluator.call([tag1, tag2], query, context:)) }
            .to make_database_queries(count: 8)
          expect { traverse(evaluator.call(Tag.all.order(:name), query, context:)) }
            .to make_database_queries(count: 9)
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(tag1, query, context:))).to eq({
            tag_name: 'Tag 1',
            taggings: [
              { taggable: { post_title: 'Post 1' } },
              { taggable: { post_title: 'Post 2' } },
              { taggable: { post_title: 'Post 3' } },
              { taggable: { comment_body: 'Comment 1' } },
              { taggable: { comment_body: 'Comment 2' } }
            ],
            taggables: [{
              post_title: 'Post 1',
              tags: [{
                tag_name: 'Tag 1',
                taggables: [
                  { post_title: 'Post 1' }, { post_title: 'Post 2' }, { post_title: 'Post 3' },
                  { comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }
                ]
              }]
            }, {
              post_title: 'Post 2',
              tags: [{
                tag_name: 'Tag 1',
                taggables: [
                  { post_title: 'Post 1' }, { post_title: 'Post 2' }, { post_title: 'Post 3' },
                  { comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }
                ]
              }, {
                tag_name: 'Tag 3',
                taggables: [{ post_title: 'Post 2' }, { post_title: 'Post 3' }, { post_title: 'Post 4' }]
              }]
            }, {
              post_title: 'Post 3',
              tags: [{
                tag_name: 'Tag 1',
                taggables: [
                  { post_title: 'Post 1' }, { post_title: 'Post 2' }, { post_title: 'Post 3' },
                  { comment_body: 'Comment 1' }, { comment_body: 'Comment 2' }
                ]
              }, {
                tag_name: 'Tag 3',
                taggables: [{ post_title: 'Post 2' }, { post_title: 'Post 3' }, { post_title: 'Post 4' }]
              }]
            }, {
              comment_body: 'Comment 1'
            }, {
              comment_body: 'Comment 2'
            }]
          })
        end
      end

      context 'with tree association queried' do
        let(:context) { { now: Time.now.utc } }
        let(:query) do
          OmniSerializer::Query.build(:root, schema: {
            resource: CategoryResource,
            members: [
              OmniSerializer::Query.build(:category_name),
              OmniSerializer::Query.build(:parent, schema: {
                resource: CategoryResource,
                members: [OmniSerializer::Query.build(:category_name)]
              }),
              OmniSerializer::Query.build(:children, schema: {
                resource: CategoryResource,
                members: [OmniSerializer::Query.build(:category_name)]
              }),
              OmniSerializer::Query.build(:published_posts, schema: {
                resource: PostCollectionResource,
                members: [
                  OmniSerializer::Query.build(:to_a, schema: {
                    resource: PostResource,
                    members: [OmniSerializer::Query.build(:post_title)]
                  }),
                  OmniSerializer::Query.build(:pagination)
                ]
              })
            ]
          })
        end

        it 'utilizes loaders' do
          expect { traverse(evaluator.call(category1, query, context:)) }
            .to make_database_queries(count: 3)
          expect { traverse(evaluator.call([category1, category2], query, context:)) }
            .to make_database_queries(count: 4)
          expect { traverse(evaluator.call(Category.all.order(:name), query, context:)) }
            .to make_database_queries(count: 5)
        end

        it 'returns resources' do
          expect(traverse(evaluator.call(category1, query, context:))).to eq({
            category_name: 'Category 1',
            parent: nil,
            children: [{ category_name: 'Category 2' }, { category_name: 'Category 3' }],
            published_posts: {
              to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            }
          })
          expect(traverse(evaluator.call(Category.all.order(:name), query, context:))).to eq([{
            category_name: 'Category 1',
            parent: nil,
            children: [{ category_name: 'Category 2' }, { category_name: 'Category 3' }],
            published_posts: {
              to_a: [{ post_title: 'Post 1' }, { post_title: 'Post 2' }],
              pagination: { total_count: 2, total_pages: 1, current_page: 1 }
            }
          }, {
            category_name: 'Category 2',
            parent: { category_name: 'Category 1' },
            children: [{ category_name: 'Category 4' }],
            published_posts: {
              to_a: [],
              pagination: { total_count: 0, total_pages: 0, current_page: 1 }
            }
          }, {
            category_name: 'Category 3',
            parent: { category_name: 'Category 1' },
            children: [],
            published_posts: {
              to_a: [{ post_title: 'Post 3' }],
              pagination: { total_count: 1, total_pages: 1, current_page: 1 }
            }
          }, {
            category_name: 'Category 4',
            parent: { category_name: 'Category 2' },
            children: [],
            published_posts: {
              to_a: [],
              pagination: { total_count: 0, total_pages: 0, current_page: 1 }
            }
          }])
        end
      end
    end
  end
end
