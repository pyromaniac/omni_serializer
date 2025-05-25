# frozen_string_literal: true

RSpec.describe OmniSerializer::Jsonapi::QueryBuilder do
  subject(:params_normalizer) { described_class.build(missing_key_formatter:, key_formatter:, type_formatter:) }

  let(:missing_key_formatter) do
    OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, casing: :snake, symbolize: true)
  end
  let(:key_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **key_formatter_options) }
  let(:key_formatter_options) { { casing: :kebab } }
  let(:type_formatter) { OmniSerializer::NameFormatter.new(inflector: Dry::Inflector.new, **type_formatter_options) }
  let(:type_formatter_options) { { casing: :kebab, number: :plural } }

  describe '#call' do
    subject(:query) { params_normalizer.call(resource, **options) }

    let(:resource) { PostResource }
    let(:options) { {} }

    context 'when some empty params are given' do
      specify do
        expect(query).to eq(OmniSerializer::Query.build(:root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            OmniSerializer::Query.build(:id),
            OmniSerializer::Query.build(:post_title),
            OmniSerializer::Query.build(:post_content)
          ]
        }))
        expect(params_normalizer.call(PostResource, include: nil, fields: nil, filter: nil, page: nil, sort: nil))
          .to eq(OmniSerializer::Query.build(:root, arguments: {}, schema: {
            resource: PostResource,
            members: [
              OmniSerializer::Query.build(:id),
              OmniSerializer::Query.build(:post_title),
              OmniSerializer::Query.build(:post_content)
            ]
          }))
        expect(params_normalizer.call(PostResource, include: '', fields: {}, filter: {}, page: {}, sort: ''))
          .to eq(OmniSerializer::Query.build(:root, arguments: { sort: {} }, schema: {
            resource: PostResource,
            members: [
              OmniSerializer::Query.build(:id),
              OmniSerializer::Query.build(:post_title),
              OmniSerializer::Query.build(:post_content)
            ]
          }))
        expect(params_normalizer.call(PostResource, include: [], filter: [], page: [], sort: []))
          .to eq(OmniSerializer::Query.build(:root, arguments: {}, schema: {
            resource: PostResource,
            members: [
              OmniSerializer::Query.build(:id),
              OmniSerializer::Query.build(:post_title),
              OmniSerializer::Query.build(:post_content)
            ]
          }))
      end
    end

    specify do
      expect { params_normalizer.call(PostResource, fields: '') }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: '`fields` parameter must be a mapping `{"type":"field1,field2"}`, given: `""`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      expect { params_normalizer.call(PostResource, fields: { posts: 'invalid' }) }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Undefined field `invalid` for `posts`, ' \
            'valid fields are: `id`, `post-title`, `post-content`, `tag-names`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      expect { params_normalizer.call(PostResource, include: 'post-author', fields: { comments: 'comment-body' }) }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid type used for query: `comments`, applicable types are: `posts`, `users`',
          status: 400,
          source: { parameter: 'fields' }
        }))
      expect { params_normalizer.call(PostResource, filter: 'foo') }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid filter parameter at `/`, must be a mapping, given: `"foo"`',
          status: 400,
          source: { parameter: 'filter' }
        }))
      expect { params_normalizer.call(PostResource, page: 'foo') }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid page parameter at `/`, must be a mapping with keys: ' \
            '`number`, `size`, `cursor`, `before`, `after`, given: `"foo"`',
          status: 400,
          source: { parameter: 'page' }
        }))
      expect { params_normalizer.call(PostResource, page: { number: 42, foo: 'bar' }) }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid page key at `/`, allowed keys are: ' \
            '`number`, `size`, `cursor`, `before`, `after`, given: `{"foo":"bar"}`',
          status: 400,
          source: { parameter: 'page' }
        }))
      expect { params_normalizer.call(PostResource, sort: 42) }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid sort parameter at `/`, must be a comma-separated list of fields, given: `42`',
          status: 400,
          source: { parameter: 'sort' }
        }))
      expect { params_normalizer.call(PostResource, 'omni:meta': '-pagination,current-page') }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Invalid omni:meta parameter at `/`, must be applied to a collection resource',
          status: 400,
          source: { parameter: 'omni:meta' }
        }))
      expect { params_normalizer.call(PostResource, 'omni:meta': { 'active-comments' => '-pagination,currentPage' }) }
        .to raise_error(an_instance_of(OmniSerializer::JsonapiError) & have_attributes(error_data: {
          detail: 'Undefined omni:meta `currentPage` at `/active-comments`, ' \
            'valid omni:meta fields are: `current-page`, `pagination`',
          status: 400,
          source: { parameter: 'omni:meta' }
        }))
    end

    context 'when include is given' do
      let(:options) { { include: 'active-comments.comment-author,post-author' } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_title, arguments: {}, schema: nil },
            { name: :post_content, arguments: {}, schema: nil },
            { name: :active_comments, arguments: {}, schema: {
              resource: CommentCollectionResource,
              members: [
                { name: :pagination, arguments: {}, schema: nil },
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
            { name: :pagination, arguments: {}, schema: nil },
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
      let(:options) { { include: 'taggables,taggings.taggable:posts.post-author' } }

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
            { name: :taggings, arguments: {}, schema: {
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
      let(:options) { { include: 'taggables:comments.comment-author,taggings.taggable:posts.post-author' } }

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
            { name: :taggings, arguments: {}, schema: {
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
      let(:options) { { include: 'parent,children,published-posts' } }

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
                { name: :published_posts, arguments: {}, schema: {
                  resource: PostCollectionResource,
                  members: [
                    { name: :pagination, arguments: {}, schema: nil },
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
                { name: :published_posts, arguments: {}, schema: {
                  resource: PostCollectionResource,
                  members: [
                    { name: :pagination, arguments: {}, schema: nil },
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
            { name: :published_posts, arguments: {}, schema: {
              resource: PostCollectionResource,
              members: [
                { name: :pagination, arguments: {}, schema: nil },
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
      let(:options) { { fields: { posts: 'post-title,active-comments' } } }

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
        {
          include: 'taggings.taggable,active-comments',
          fields: { taggings: '', posts: 'id,tag-names', comments: 'comment-body', 'comment-collections' => '' }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag_names, arguments: {}, schema: nil },
            { name: :taggings, arguments: {}, schema: {
              resource: TaggingResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :taggable, arguments: {}, schema: {
                  Post => {
                    resource: PostResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :tag_names, arguments: {}, schema: nil },
                      { name: :taggings, arguments: {}, schema: {
                        resource: TaggingResource,
                        members: [{ name: :id, arguments: {}, schema: nil }]
                      } },
                      { name: :active_comments, arguments: {}, schema: {
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
            { name: :active_comments, arguments: {}, schema: {
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
      let(:options) { { filter: { 'post-title': 'foo', 'active-comments': { nested: 42 }, 'non-member' => 'value' } } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root,
          arguments: { filter: { post_title: 'foo', non_member: 'value' } }, schema: {
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
      let(:options) do
        {
          include: 'active-comments,tags',
          filter: {
            'active-comments' => { 'comment-body' => 'hello' },
            'tags' => { 'name' => 'world' }
          }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root,
          arguments: {}, schema: {
            resource: PostResource,
            members: [
              { name: :id, arguments: {}, schema: nil },
              { name: :post_title, arguments: {}, schema: nil },
              { name: :post_content, arguments: {}, schema: nil },
              { name: :active_comments, arguments: { filter: { comment_body: 'hello' } }, schema: {
                resource: CommentCollectionResource,
                members: [
                  { name: :pagination, arguments: {}, schema: nil },
                  { name: :to_a, arguments: {}, schema: {
                    resource: CommentResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :comment_body, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              } },
              { name: :tags, arguments: { filter: { name: 'world' } }, schema: {
                resource: TagResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :tag_name, arguments: {}, schema: nil }
                ]
              } }
            ]
          }))
      end
    end

    context 'when filter is given for deeply included member' do
      let(:resource) { UserResource }
      let(:options) do
        {
          include: 'posts.active-comments,comments',
          filter: {
            'posts.active-comments': { 'comment-body' => ['hello'] },
            posts: {
              'post-title': 'foobar',
              'active-comments': { 'comment-body': [{}], 'non-member': 'value' }
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
              members: [
                { name: :pagination, arguments: {}, schema: nil },
                { name: :to_a, arguments: {}, schema: {
                  resource: PostResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :post_title, arguments: {}, schema: nil },
                    { name: :post_content, arguments: {}, schema: nil },
                    {
                      name: :active_comments,
                      arguments: { filter: { comment_body: ['hello', {}], non_member: 'value' } },
                      schema: {
                        resource: CommentCollectionResource,
                        members: [
                          { name: :pagination, arguments: {}, schema: nil },
                          { name: :to_a, arguments: {}, schema: {
                            resource: CommentResource,
                            members: [
                              { name: :id, arguments: {}, schema: nil },
                              { name: :comment_body, arguments: {}, schema: nil }
                            ]
                          } }
                        ]
                      }
                    }
                  ]
                } }
              ]
            } },
            { name: :comments, arguments: {}, schema: {
              resource: CommentCollectionResource,
              members: [
                { name: :pagination, arguments: {}, schema: nil },
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

    context 'when page is given' do
      let(:resource) { PostResource }
      let(:options) do
        {
          include: 'active-comments',
          page: {
            'number' => 2,
            'size' => 10,
            'active-comments' => {
              'cursor' => '123',
              'before' => '456',
              'after' => '789'
            }
          }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(
          name: :root,
          arguments: { page: { number: 2, size: 10 } },
          schema: {
            resource: PostResource,
            members: [
              { name: :id, arguments: {}, schema: nil },
              { name: :post_title, arguments: {}, schema: nil },
              { name: :post_content, arguments: {}, schema: nil },
              {
                name: :active_comments,
                arguments: { page: { cursor: '123', before: '456', after: '789' } },
                schema: {
                  resource: CommentCollectionResource,
                  members: [
                    { name: :pagination, arguments: {}, schema: nil },
                    { name: :to_a, arguments: {}, schema: {
                      resource: CommentResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :comment_body, arguments: {}, schema: nil }
                      ]
                    } }
                  ]
                }
              }
            ]
          }
        ))
      end
    end

    context 'when sort is given' do
      let(:resource) { PostResource }
      let(:options) do
        {
          include: 'active-comments',
          sort: [
            'post-title,active-comments,-active-comments,-postTitle',
            { 'active-comments' => '-comment-body,posts,commentAuthor' }
          ]
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(
          name: :root,
          arguments: { sort: { post_title: :desc, active_comments: :desc } },
          schema: {
            resource: PostResource,
            members: [
              { name: :id, arguments: {}, schema: nil },
              { name: :post_title, arguments: {}, schema: nil },
              { name: :post_content, arguments: {}, schema: nil },
              {
                name: :active_comments,
                arguments: { sort: { comment_body: :desc, posts: :asc, comment_author: :asc } },
                schema: {
                  resource: CommentCollectionResource,
                  members: [
                    { name: :pagination, arguments: {}, schema: nil },
                    { name: :to_a, arguments: {}, schema: {
                      resource: CommentResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :comment_body, arguments: {}, schema: nil }
                      ]
                    } }
                  ]
                }
              }
            ]
          }
        ))
      end
    end

    context 'when omni:meta is given' do
      let(:resource) { PostCollectionResource }
      let(:options) do
        {
          include: 'active-comments',
          'omni:meta': [
            '-pagination',
            { 'active-comments' => 'current-page,-pagination' }
          ]
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root,
          arguments: {}, schema: {
            resource: PostCollectionResource,
            members: [
              { name: :to_a, arguments: {}, schema: {
                resource: PostResource,
                members: [
                  { name: :id, arguments: {}, schema: nil },
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_content, arguments: {}, schema: nil },
                  { name: :active_comments, arguments: {}, schema: {
                    resource: CommentCollectionResource,
                    members: [
                      { name: :current_page, arguments: {}, schema: nil },
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
              } }
            ]
          }))
      end
    end
  end
end
