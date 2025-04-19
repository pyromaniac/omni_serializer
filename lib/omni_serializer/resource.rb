# frozen_string_literal: true

class OmniSerializer::Resource
  extend Dry::Initializer

  COLLECTION_MEMBER = :to_a

  param :object, OmniSerializer::Types::Any
  option :cache, OmniSerializer::Types::Interface(:fetch)
  option :loaders, OmniSerializer::Types::Interface(:loader)
  option :context, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)
  option :arguments, OmniSerializer::Types::Hash.map(OmniSerializer::Types::Symbol, OmniSerializer::Types::Any)

  class << self
    def type(name = nil, &block)
      if name || block
        @type = name
        @type_block = block
      else
        @type ||= (instance_exec(&type_block) if type_block)
      end
    end

    def type_block
      @type_block || (superclass.type_block if superclass.respond_to?(:type_block))
    end

    def members
      @members ||= superclass.respond_to?(:members) ? superclass.members : {}
    end

    def attribute(name, **options, &block)
      define_member(Member.new(name:, macro: :attribute, expose: true, **options, condition: options[:if],
        evaluator: block))
    end

    def attributes(*names)
      names.each { |name| attribute(name) }
    end

    def meta(name, **options, &block)
      define_member(Member.new(name:, macro: :meta, expose: false, **options, condition: options[:if],
        evaluator: block))
    end

    def has_one(name, **, &) # rubocop:disable Naming/PredicateName
      association(name, **, collection: false, &)
    end

    def has_many(name, **, &) # rubocop:disable Naming/PredicateName
      association(name, **, collection: true, &)
    end

    def collection(...)
      has_many(COLLECTION_MEMBER, ...)
    end

    def collection?
      members.key?(COLLECTION_MEMBER)
    end

    def collection_member
      members[COLLECTION_MEMBER]
    end

    private

    def association(name, **options, &block)
      define_member(Association.new(name:, **options, condition: options[:if], evaluator: block))
    end

    def define_member(member)
      @members = members.merge(member.name => member)
      define_reader(member)
      member
    end

    def define_reader(member)
      condition = if member.condition.is_a?(Symbol)
        "return unless #{member.condition}"
      elsif member.condition
        "return unless instance_exec(&self.class.members[:#{member.name}].condition)"
      end

      evaluation = if member.evaluator
        "instance_exec(**kwargs, &self.class.members[:#{member.name}].evaluator)"
      else
        "object.#{member.name}"
      end

      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{member.name}(**kwargs)
          #{condition}
          #{evaluation}
        end
      RUBY
    end
  end
end
