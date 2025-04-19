# frozen_string_literal: true

RSpec.describe OmniSerializer::Resource do
  let(:cache) { OmniSerializer::Cache.new }
  let(:loaders) { OmniSerializer::Loaders.new({}) }

  describe '.type' do
    before { stub_class(:dummy_resource, described_class) }

    specify { expect(DummyResource.type).to be_nil }

    context 'when a type is set' do
      before { DummyResource.type('test') }

      specify { expect(DummyResource.type).to eq('test') }
    end

    context 'when a block is given' do
      before { DummyResource.type { name.delete_suffix('Resource') } }

      specify { expect(DummyResource.type).to eq('Dummy') }
    end

    context 'with inheritance' do
      before { stub_class(:inherited_dummy_resource, DummyResource) }

      context 'when a type is set on the base class' do
        before { DummyResource.type('test') }

        specify do
          expect(DummyResource.type).to eq('test')
          expect(InheritedDummyResource.type).to be_nil
        end
      end

      context 'when a type is set on the base class with a block' do
        before { DummyResource.type { name.delete_suffix('Resource') } }

        specify do
          expect(DummyResource.type).to eq('Dummy')
          expect(InheritedDummyResource.type).to eq('InheritedDummy')
        end

        context 'when the third level class inherits block from the base level class' do
          before do
            InheritedDummyResource.type('inherited')
            stub_class(:inherited_inherited_dummy_resource, InheritedDummyResource)
          end

          specify do
            expect(DummyResource.type).to eq('Dummy')
            expect(InheritedDummyResource.type).to eq('inherited')
            expect(InheritedInheritedDummyResource.type).to eq('InheritedInheritedDummy')
          end
        end
      end

      context 'when a type is set on the inherited class with a block' do
        before { InheritedDummyResource.type { name.delete_suffix('Resource') } }

        specify do
          expect(DummyResource.type).to be_nil
          expect(InheritedDummyResource.type).to eq('InheritedDummy')
        end
      end
    end
  end

  describe '.members' do
    before do
      stub_class(:comment_resource, described_class) do
        attributes :body
      end

      stub_class(:user_resource, described_class) do
        attribute :name
      end

      stub_class(:post_resource, described_class) do
        attributes :title
        has_one :user, resource: 'UserResource'
        has_many :comments, resource: 'CommentResource'
        meta :comments_count
      end
    end

    specify do
      expect(PostResource.members).to match({
        title: an_instance_of(described_class::Member) & have_attributes(name: :title),
        user: an_instance_of(described_class::Association) &
          have_attributes(name: :user, collection: false, resource: 'UserResource'),
        comments: an_instance_of(described_class::Association) &
          have_attributes(name: :comments, collection: true, resource: 'CommentResource'),
        comments_count: an_instance_of(described_class::Member) & have_attributes(name: :comments_count)
      })
    end

    context 'with inheritance' do
      before do
        stub_class(:inherited_post_resource, PostResource) do
          attributes :title, :content
          attribute :user
          meta :comments
        end
      end

      specify do
        expect(PostResource.members).to match({
          title: an_instance_of(described_class::Member) & have_attributes(name: :title),
          user: an_instance_of(described_class::Association) &
            have_attributes(name: :user, collection: false, resource: 'UserResource'),
          comments: an_instance_of(described_class::Association) &
            have_attributes(name: :comments, collection: true, resource: 'CommentResource'),
          comments_count: an_instance_of(described_class::Member) & have_attributes(name: :comments_count)
        })

        expect(InheritedPostResource.members).to match({
          title: an_instance_of(described_class::Member) & have_attributes(name: :title),
          content: an_instance_of(described_class::Member) & have_attributes(name: :content),
          user: an_instance_of(described_class::Member) & have_attributes(name: :user),
          comments: an_instance_of(described_class::Member) & have_attributes(name: :comments),
          comments_count: an_instance_of(described_class::Member) & have_attributes(name: :comments_count)
        })
      end
    end
  end

  describe '.attribute' do
    subject(:resource) do
      PostResource.new(object, cache:, loaders:, context:, arguments:)
    end

    let(:context) { {} }
    let(:arguments) { {} }
    let(:object) { Post.new(title: 'Hello, world!') }

    before do
      stub_class(:post_resource, described_class) do
        attribute :title
      end
    end

    specify do
      expect(resource).to respond_to(:title)
      expect(resource.title).to eq('Hello, world!')
    end

    context 'when block is given' do
      before do
        stub_class(:post_resource, described_class) do
          attribute :title do
            object_title_upcase
          end

          private

          def object_title_upcase
            object.title.upcase
          end
        end
      end

      specify { expect(resource.title).to eq('HELLO, WORLD!') }
    end

    context 'when condition is given' do
      before do
        stub_class(:post_resource, described_class) do
          attribute :title, if: -> { context[:admin] }
        end
      end

      specify { expect(resource.title).to be_nil }

      context 'when condition is true' do
        let(:context) { { admin: true } }

        specify { expect(resource.title).to eq('Hello, world!') }
      end
    end

    context 'when condition is a symbol' do
      before do
        stub_class(:post_resource, described_class) do
          attribute :title, if: :admin? do
            object.title.upcase
          end

          private

          def admin?
            context[:admin]
          end
        end
      end

      specify { expect(resource.title).to be_nil }

      context 'when condition is true' do
        let(:context) { { admin: true } }

        specify { expect(resource.title).to eq('HELLO, WORLD!') }
      end
    end
  end

  describe '.attributes' do
    before do
      stub_class(:post_resource, described_class) do
        attributes :title, :content
      end
    end

    specify do
      expect(PostResource.members).to match({
        title: an_instance_of(described_class::Member) & have_attributes(name: :title),
        content: an_instance_of(described_class::Member) & have_attributes(name: :content)
      })
    end
  end

  describe '.has_one' do
    subject(:resource) do
      PostResource.new(post, cache:, loaders:, context:, arguments:)
    end

    let(:context) { {} }
    let(:arguments) { {} }
    let(:post) { Post.new(user:) }
    let(:user) { User.new(name: 'John Doe') }

    before do
      stub_class(:user_resource, described_class) do
        attribute :name
      end

      stub_class(:post_resource, described_class) do
        has_one :user, resource: 'UserResource'
      end
    end

    specify do
      expect(resource).to respond_to(:user)
      expect(resource.user).to eq(user)
    end

    context 'when block is given' do
      before do
        stub_class(:post_resource, described_class) do
          has_one :user, resource: 'UserResource' do
            object_user
          end

          private

          def object_user
            object.user
          end
        end
      end

      specify { expect(resource.user).to eq(user) }
    end
  end

  describe '.meta' do
    subject(:resource) do
      CommentsCollectionResource.new(comments, cache:, loaders:, context:, arguments:)
    end

    let(:context) { {} }
    let(:arguments) { {} }
    let(:comments) { [Comment.new(body: 'Comment 1'), Comment.new(body: 'Comment 2')] }

    before do
      stub_class(:comments_collection_resource, described_class) do
        meta :total_count do
          object_size
        end

        private

        def object_size
          object.size
        end
      end
    end

    specify do
      expect(resource).to respond_to(:total_count)
      expect(resource.total_count).to eq(2)
    end
  end

  describe '.has_many' do
    subject(:resource) do
      PostResource.new(post, cache:, loaders:, context:, arguments:)
    end

    let(:context) { {} }
    let(:arguments) { {} }
    let(:post) { Post.new(comments:) }
    let(:comments) { [Comment.new(body: 'Comment 1'), Comment.new(body: 'Comment 2')] }

    before do
      stub_class(:comment_resource, described_class) do
        attribute :body
      end

      stub_class(:post_resource, described_class) do
        has_many :comments, resource: 'CommentResource'
      end
    end

    specify do
      expect(resource).to respond_to(:comments)
      expect(resource.comments).to eq(comments)
    end

    context 'when block is given' do
      before do
        stub_class(:post_resource, described_class) do
          has_many :comments, resource: 'CommentResource' do
            object_comments_first_one
          end

          private

          def object_comments_first_one
            object.comments.first(1)
          end
        end
      end

      specify { expect(resource.comments).to eq([comments.first]) }
    end
  end

  describe '.collection' do
    subject(:resource) do
      CommentsCollectionResource.new(comments, cache:, loaders:, context:, arguments:)
    end

    let(:context) { {} }
    let(:arguments) { {} }
    let(:comments) { [Comment.new(body: 'Comment 1'), Comment.new(body: 'Comment 2')] }

    before do
      stub_class(:comment_resource, described_class) do
        attribute :body
      end

      stub_class(:comments_collection_resource, described_class) do
        collection resource: 'CommentResource'
      end
    end

    specify do
      expect(CommentsCollectionResource.members).to match({
        to_a: an_instance_of(described_class::Association) &
          have_attributes(name: :to_a, collection: true, resource: 'CommentResource')
      })
      expect(resource).to respond_to(:to_a)
      expect(resource.to_a).to eq(comments)
    end

    context 'when block is given' do
      let(:arguments) { { limit: 1 } }

      before do
        stub_class(:comments_collection_resource, described_class) do
          collection resource: 'CommentResource' do
            object_comments_first_limit
          end

          private

          def object_comments_first_limit
            object.first(arguments[:limit])
          end
        end
      end

      specify { expect(resource.to_a).to eq([comments.first]) }
    end
  end
end
