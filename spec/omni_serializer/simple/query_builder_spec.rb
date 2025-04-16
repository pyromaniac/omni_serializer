# frozen_string_literal: true

RSpec.describe OmniSerializer::Simple::QueryBuilder do
  subject(:query_builder) { described_class.new }

  describe '#call' do
    subject(:query) { query_builder.call(resource, **options) }

    let(:resource) { PostResource }
    let(:options) { {} }

    specify do
      expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
        resource: PostResource,
        members: [
          { name: :id, arguments: {}, schema: nil },
          { name: :post_title, arguments: {}, schema: nil },
          { name: :post_content, arguments: {}, schema: nil }
        ]
      }))
    end

    context 'when only: is given' do
      let(:options) { { only: :post_title, except: :invalid, extra: nil } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [{ name: :post_title, arguments: {}, schema: nil }]
        }))
      end
    end

    context 'when except: is given' do
      let(:options) { { only: nil, except: :post_title, extra: :invalid } }

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_content, arguments: {}, schema: nil }
          ]
        }))
      end
    end

    context 'when extra: is given' do
      let(:options) do
        {
          only: %i[post_title tags],
          except: :invalid,
          extra: :comments_count,
          params: { foo: 42 },
          include: %i[post_author comments]
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: { foo: 42 }, schema: {
          resource: PostResource,
          members: [
            { name: :post_title, arguments: {}, schema: nil },
            { name: :comments_count, arguments: {}, schema: nil },
            { name: :post_author, arguments: {}, schema: {
              resource: UserResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :user_name, arguments: {}, schema: nil }
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

    context 'when include: is given' do
      let(:resource) { CommentResource }
      let(:options) do
        { include: { post: { only: { post_title: { bar: 43 } }, include: :post_author, params: { foo: 42 } } } }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: CommentResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :comment_body, arguments: {}, schema: nil },
            { name: :post, arguments: { foo: 42 }, schema: {
              resource: PostResource,
              members: [
                { name: :post_title, arguments: { bar: 43 }, schema: nil },
                { name: :post_author, arguments: {}, schema: {
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

    context 'with collection resource' do
      let(:resource) { CommentCollectionResource }
      let(:options) do
        { include: { post: { only: :post_title, include: :post_author, params: { foo: 42 } } }, params: { bar: 43 } }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: { bar: 43 }, schema: {
          resource: CommentCollectionResource,
          members: [
            { name: :to_a, arguments: {}, schema: {
              resource: CommentResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :comment_body, arguments: {}, schema: nil },
                { name: :post, arguments: { foo: 42 }, schema: {
                  resource: PostResource,
                  members: [
                    { name: :post_title, arguments: {}, schema: nil },
                    { name: :post_author, arguments: {}, schema: {
                      resource: UserResource,
                      members: [
                        { name: :id, arguments: {}, schema: nil },
                        { name: :user_name, arguments: {}, schema: nil }
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

    context 'with collection resource on lower level' do
      let(:resource) { PostResource }
      let(:options) do
        {
          include: {
            comments: {
              collection: { extra: [:total_count] },
              only: [:id, { comment_body: { bar: 43 } }],
              include: { comment_author: { except: :user_name } },
              params: { foo: 42 }
            }
          }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: PostResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :post_title, arguments: {}, schema: nil },
            { name: :post_content, arguments: {}, schema: nil },
            { name: :comments, arguments: { foo: 42 }, schema: {
              resource: CommentCollectionResource,
              members: [
                { name: :to_a, arguments: {}, schema: {
                  resource: CommentResource,
                  members: [
                    { name: :id, arguments: {}, schema: nil },
                    { name: :comment_body, arguments: { bar: 43 }, schema: nil },
                    { name: :comment_author, arguments: {}, schema: {
                      resource: UserResource,
                      members: [{ name: :id, arguments: {}, schema: nil }]
                    } }
                  ]
                } },
                { name: :total_count, arguments: {}, schema: nil }
              ]
            } }
          ]
        }))
      end
    end

    context 'with polymorphic association' do
      let(:resource) { TaggingResource }
      let(:options) do
        {
          include: [:tag, {
            taggable: {
              only: [:post_title, :comment_body, { comments: { foo: 42 } }],
              include: { post_author: { extra: [:comments_count, { posts_count: { bar: 43 } }] } }
            }
          }]
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: TaggingResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag, arguments: {}, schema: {
              resource: TagResource,
              members: [
                { name: :id, arguments: {}, schema: nil },
                { name: :tag_name, arguments: {}, schema: nil }
              ]
            } },
            { name: :taggable, arguments: {}, schema: {
              Post => {
                resource: PostResource,
                members: [
                  { name: :post_title, arguments: {}, schema: nil },
                  { name: :post_author, arguments: {}, schema: {
                    resource: UserResource,
                    members: [
                      { name: :id, arguments: {}, schema: nil },
                      { name: :user_name, arguments: {}, schema: nil },
                      { name: :comments_count, arguments: {}, schema: nil },
                      { name: :posts_count, arguments: { bar: 43 }, schema: nil }
                    ]
                  } }
                ]
              },
              Comment => {
                resource: CommentResource,
                members: [{ name: :comment_body, arguments: {}, schema: nil }]
              }
            } }
          ]
        }))
      end
    end

    context 'with polymorphic association per-type query options' do
      let(:resource) { TagResource }
      let(:options) do
        {
          include: { taggables: { params: { foo: 42 }, types: { PostResource => { include: :tags } }, except: :id } }
        }
      end

      specify do
        expect(query).to eq(OmniSerializer::Query.new(name: :root, arguments: {}, schema: {
          resource: TagResource,
          members: [
            { name: :id, arguments: {}, schema: nil },
            { name: :tag_name, arguments: {}, schema: nil },
            { name: :taggables, arguments: { foo: 42 }, schema: {
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
                      { name: :tag_name, arguments: {}, schema: nil }
                    ]
                  } }
                ]
              },
              Comment => {
                resource: CommentResource,
                members: [{ name: :comment_body, arguments: {}, schema: nil }]
              }
            } }
          ]
        }))
      end
    end
  end
end
