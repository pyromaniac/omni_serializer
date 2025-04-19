# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::QueryBuilder do
  subject(:params_normalizer) { described_class.new(key_formatter:, type_formatter:) }

  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }

  describe '#call' do
    subject(:query) { params_normalizer.call(resource, **options) }

    let(:resource) { PostResource }
    let(:options) { {} }

    context 'when some empty params are given' do
      let(:default_post_query) do
        OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_title, arguments: {}, schema: nil },
            { name: :post_content, arguments: {}, schema: nil }
          ]
        })
      end

      specify do
        expect(query).to eq(default_post_query)
        expect(params_normalizer.call(PostResource, include: nil, fields: nil, filter: nil, sort: nil))
          .to eq(default_post_query)
        expect(params_normalizer.call(PostResource, include: '', sort: '')).to eq(default_post_query)
        expect(params_normalizer.call(PostResource, include: [], sort: [])).to eq(default_post_query)
      end

      specify do
        expect { params_normalizer.call(PostResource, fields: '') }
          .to raise_error(OmniSerializer::Error, '`fields` parameter must be an mapping')
        expect { params_normalizer.call(PostResource, fields: { posts: 'invalid' }) }
          .to raise_error(OmniSerializer::UndefinedMember, 'Undefined member: `invalid` for `PostResource`')
        expect { params_normalizer.call(PostResource, include: 'post-author', fields: { comments: 'comment-body' }) }
          .to raise_error(OmniSerializer::UndefinedQueryType,
            'Undefined type: `comments`, query types: `posts`, `users`')
        expect { params_normalizer.call(PostResource, filter: '') }
          .to raise_error(OmniSerializer::Error, '`filter` parameter must be an mapping')
      end
    end

    context 'when include is given' do
      let(:options) { { include: 'comments.comment-author,post-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_title, arguments: {}, schema: nil },
            { name: :post_content, arguments: {}, schema: nil },
            { name: :comments, arguments: {}, schema: {
              resource: CommentCollectionResource,
              members: [
                { name: :to_a, arguments: {}, schema: {
                  resource: CommentResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :comment_body, arguments: {}, schema: nil },
                    { name: :comment_author, arguments: {}, schema: {
                      resource: UserResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :user_name, arguments: {}, schema: nil }
                      ]
                    } }
                  ]
                } }
              ]
            } },
            { name: :post_author, arguments: {}, schema: {
              resource: UserResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :user_name, arguments: {}, schema: nil }
              ]
            } }
          ]
        }))
      end
    end

    context 'with top-level collection' do
      let(:resource) { CommentCollectionResource }
      let(:options) { { include: 'comment-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: CommentCollectionResource,
          members: [
            { name: :to_a, arguments: {}, schema: {
              resource: CommentResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :comment_body, arguments: {}, schema: nil },
                { name: :comment_author, arguments: {}, schema: {
                  resource: UserResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :user_name, arguments: {}, schema: nil }
                  ]
                } }
              ]
            } }
          ]
        }))
      end
    end

    context 'when include is polymorphic' do
      let(:resource) { TagResource }
      let(:options) { { include: 'taggables,tagging.taggable:posts.post-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: TagResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag_name, arguments: {}, schema: nil },
            { name: :taggables, arguments: {}, schema: {
              Post => {
                resource: PostResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_content, arguments: {}, schema: nil },
                  { name: :post_author, arguments: {}, schema: {
                    resource: UserResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :user_name, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              },
              Comment => {
                resource: CommentResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :comment_body, arguments: {}, schema: nil }
                ]
              }
            } },
            { name: :tagging, arguments: {}, schema: {
              resource: TaggingResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :taggable, arguments: {}, schema: {
                  Post => {
                    resource: PostResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :post_title, arguments: {}, schema: nil },
                      { name: :post_content, arguments: {}, schema: nil },
                      { name: :post_author, arguments: {}, schema: {
                        resource: UserResource,
                        members: [
                          { name: :id, arguments: {}, schema: nil },
                          { name: :user_name, arguments: {}, schema: nil }
                        ]
                      } }
                    ]
                  },
                  Comment => {
                    resource: CommentResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :comment_body, arguments: {}, schema: nil }
                    ]
                  }
                } }
              ]
            } }
          ]
        }))
      end
    end

    context 'when include is polymorphic with types expanded on different levels' do
      let(:resource) { TagResource }
      let(:options) { { include: 'taggables:comments.comment-author,tagging.taggable:posts.post-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: TagResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag_name, arguments: {}, schema: nil },
            { name: :taggables, arguments: {}, schema: {
              Post => {
                resource: PostResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_content, arguments: {}, schema: nil },
                  { name: :post_author, arguments: {}, schema: {
                    resource: UserResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :user_name, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              },
              Comment => {
                resource: CommentResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :comment_body, arguments: {}, schema: nil },
                  { name: :comment_author, arguments: {}, schema: {
                    resource: UserResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :user_name, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              }
            } },
            { name: :tagging, arguments: {}, schema: {
              resource: TaggingResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :taggable, arguments: {}, schema: {
                  Post => {
                    resource: PostResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :post_title, arguments: {}, schema: nil },
                      { name: :post_content, arguments: {}, schema: nil },
                      { name: :post_author, arguments: {}, schema: {
                        resource: UserResource,
                        members: [
                          { name: :id, arguments: {}, schema: nil },
                          { name: :user_name, arguments: {}, schema: nil }
                        ]
                      } }
                    ]
                  },
                  Comment => {
                    resource: CommentResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :comment_body, arguments: {}, schema: nil },
                      { name: :comment_author, arguments: {}, schema: {
                        resource: UserResource,
                        members: [
                          { name: :id, arguments: {}, schema: nil },
                          { name: :user_name, arguments: {}, schema: nil }
                        ]
                      } }
                    ]
                  }
                } }
              ]
            } }
          ]
        }))
      end
    end

    context 'when include is recursive' do
      let(:resource) { CategoryResource }
      let(:options) { { include: 'parent,children,posts' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: CategoryResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :category_name, arguments: {}, schema: nil },
            { name: :parent, arguments: {}, schema: {
              resource: CategoryResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :category_name, arguments: {}, schema: nil },
                { name: :parent, arguments: {}, schema: {
                  resource: CategoryResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :category_name, arguments: {}, schema: nil }
                  ]
                } },
                { name: :children, arguments: {}, schema: {
                  resource: CategoryResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :category_name, arguments: {}, schema: nil }
                  ]
                } },
                { name: :posts, arguments: {}, schema: {
                  resource: PostCollectionResource,
                  members: [
                    { name: :to_a, arguments: {}, schema: {
                      resource: PostResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :post_title, arguments: {}, schema: nil },
                        { name: :post_content, arguments: {}, schema: nil }
                      ]
                    } }
                  ]
                } }
              ]
            } },
            { name: :children, arguments: {}, schema: {
              resource: CategoryResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :category_name, arguments: {}, schema: nil },
                { name: :parent, arguments: {}, schema: {
                  resource: CategoryResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :category_name, arguments: {}, schema: nil }
                  ]
                } },
                { name: :children, arguments: {}, schema: {
                  resource: CategoryResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :category_name, arguments: {}, schema: nil }
                  ]
                } },
                { name: :posts, arguments: {}, schema: {
                  resource: PostCollectionResource,
                  members: [
                    { name: :to_a, arguments: {}, schema: {
                      resource: PostResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :post_title, arguments: {}, schema: nil },
                        { name: :post_content, arguments: {}, schema: nil }
                      ]
                    } }
                  ]
                } }
              ]
            } },
            { name: :posts, arguments: {}, schema: {
              resource: PostCollectionResource,
              members: [
                { name: :to_a, arguments: {}, schema: {
                  resource: PostResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :post_title, arguments: {}, schema: nil },
                    { name: :post_content, arguments: {}, schema: nil }
                  ]
                } }
              ]
            } }
          ]
        }))
      end
    end

    context 'when include is circular' do
      let(:resource) { TagResource }
      let(:options) { { include: 'taggables.tags,taggables:comments.comment-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: TagResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag_name, arguments: {}, schema: nil },
            { name: :taggables, arguments: {}, schema: {
              Post => {
                resource: PostResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_content, arguments: {}, schema: nil },
                  { name: :tags, arguments: {}, schema: {
                    resource: TagResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :tag_name, arguments: {}, schema: nil },
                      { name: :taggables, arguments: {}, schema: {
                        Post => {
                          resource: PostResource,
                          members: [
                            { name: :id, arguments: {}, schema: nil },
                            { name: :post_title, arguments: {}, schema: nil },
                            { name: :post_content, arguments: {}, schema: nil }
                          ]
                        },
                        Comment => {
                          resource: CommentResource,
                          members: [
                            { name: :id, arguments: {}, schema: nil },
                            { name: :comment_body, arguments: {}, schema: nil }
                          ]
                        }
                      } }
                    ]
                  } }
                ]
              },
              Comment => {
                resource: CommentResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :comment_body, arguments: {}, schema: nil },
                  { name: :tags, arguments: {}, schema: {
                    resource: TagResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :tag_name, arguments: {}, schema: nil },
                      { name: :taggables, arguments: {}, schema: {
                        Post => {
                          resource: PostResource,
                          members: [
                            { name: :id, arguments: {}, schema: nil },
                            { name: :post_title, arguments: {}, schema: nil },
                            { name: :post_content, arguments: {}, schema: nil }
                          ]
                        },
                        Comment => {
                          resource: CommentResource,
                          members: [
                            { name: :id, arguments: {}, schema: nil },
                            { name: :comment_body, arguments: {}, schema: nil }
                          ]
                        }
                      } }
                    ]
                  } },
                  { name: :comment_author, arguments: {}, schema: {
                    resource: UserResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :user_name, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              }
            } }
          ]
        }))
      end
    end

    context 'when fields are given' do
      let(:resource) { PostResource }
      let(:options) { { fields: { posts: 'post-title,comments' } } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_title, arguments: {}, schema: nil }
          ]
        }))
      end
    end

    context 'when fields and includes are given' do
      let(:resource) { PostResource }
      let(:options) do
        { include: 'taggings.taggable,comments', fields: { taggings: '', posts: 'id', comments: 'comment-body' } }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :taggings, arguments: {}, schema: {
              resource: TaggingResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :taggable, arguments: {}, schema: {
                  Post => {
                    resource: PostResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :taggings, arguments: {}, schema: {
                        resource: TaggingResource,
                        members: [{ name: :id, arguments: {}, schema: nil }]
                      } },
                      { name: :comments, arguments: {}, schema: {
                        resource: CommentCollectionResource,
                        members: [{ name: :to_a, arguments: {}, schema: {
                          resource: CommentResource,
                          members: [
                            { name: :id, arguments: {}, schema: nil },
                            { name: :comment_body, arguments: {}, schema: nil }
                          ]
                        } }]
                      } }
                    ]
                  },
                  Comment => {
                    resource: CommentResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :comment_body, arguments: {}, schema: nil }
                    ]
                  }
                } }
              ]
            } },
            { name: :comments, arguments: {}, schema: {
              resource: CommentCollectionResource,
              members: [
                { name: :to_a, arguments: {}, schema: {
                  resource: CommentResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :comment_body, arguments: {}, schema: nil }
                  ]
                } }
              ]
            } }
          ]
        }))
      end
    end

    context 'when filter is given' do
      let(:resource) { PostResource }
      let(:options) { { filter: { 'post-title': 'foo', comments: { nested: 42 }, 'non-member' => 'value' } } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root,
          arguments: { filter: { post_title: 'foo', 'non-member' => 'value' } }, schema: {
            resource: PostResource,
            members: [
              { name: :id, arguments: {}, schema: nil },
              { name: :post_title, arguments: {}, schema: nil },
              { name: :post_content, arguments: {}, schema: nil }
            ]
          }))
      end
    end

    context 'when filter is given for included member' do
      let(:resource) { PostResource }
      let(:options) { { include: 'comments', filter: { comments: { 'comment-body': 'hello' } } } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root,
          arguments: {}, schema: {
            resource: PostResource,
            members: [
              { name: :id, arguments: {}, schema: nil },
              { name: :post_title, arguments: {}, schema: nil },
              { name: :post_content, arguments: {}, schema: nil },
              { name: :comments, arguments: { filter: { comment_body: 'hello' } }, schema: {
                resource: CommentCollectionResource,
                members: [{ name: :to_a, arguments: {}, schema: {
                  resource: CommentResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :comment_body, arguments: {}, schema: nil }
                  ]
                } }]
              } }
            ]
          }))
      end
    end

    context 'when filter is given for deeply included member' do
      let(:resource) { UserResource }
      let(:options) do
        {
          include: 'posts.comments,comments',
          filter: {
            'posts.comments': { 'comment-body' => ['hello'] },
            posts: {
              'post-title': 'foobar',
              comments: { 'comment-body': [{}], 'non-member': 'value' }
            }
          }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: UserResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :user_name, arguments: {}, schema: nil },
            { name: :posts, arguments: { filter: { post_title: 'foobar' } }, schema: {
              resource: PostCollectionResource,
              members: [{ name: :to_a, arguments: {}, schema: {
                resource: PostResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_content, arguments: {}, schema: nil },
                  {
                    name: :comments,
                    arguments: { filter: { comment_body: ['hello', {}], 'non-member' => 'value' } },
                    schema: {
                      resource: CommentCollectionResource,
                      members: [{ name: :to_a, arguments: {}, schema: {
                        resource: CommentResource,
                        members: [
                          { name: :id, arguments: {}, schema: nil },
                          { name: :comment_body, arguments: {}, schema: nil }
                        ]
                      } }]
                    }
                  }
                ]
              } }]
            } },
            { name: :comments, arguments: {}, schema: {
              resource: CommentCollectionResource,
              members: [{ name: :to_a, arguments: {}, schema: {
                resource: CommentResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :comment_body, arguments: {}, schema: nil }
                ]
              } }]
            } }
          ]
        }))
      end
    end
  end
end
