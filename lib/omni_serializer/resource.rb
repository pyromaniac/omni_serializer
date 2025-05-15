# frozen_string_literal: true

class OmniSerializer::Resource
  extend Dry::Initializer

  COLLECTION_MEMBER = :to_a

  param :object, OmniSerializer::Types::Any
  option :parent, OmniSerializer::Types::Any
  option :path, OmniSerializer::Types::Array.of(OmniSerializer::Types::Symbol | OmniSerializer::Types::Integer)
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
      define_member(Member.new(name:, macro: :attribute, expose: true,
        **options, condition: options[:if], evaluator: block))
    end

    def attributes(*names, **options)
      names.each { |name| attribute(name, **options) }
    end

    def meta(name, **options, &block)
      define_member(Member.new(name:, macro: :meta, expose: false,
        **options, condition: options[:if], evaluator: block))
    end

    def one(name, **, &)
      association(name, **, collection: false, &)
    end
    alias has_one one

    def many(name, **, &)
      association(name, **, collection: true, &)
    end
    alias has_many many

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

      define_method(member.name) do |**arguments|
        evaluate(member.name, **arguments)
      end

      member
    end
  end

  def evaluate(name, **)
    member = self.class.members.fetch(name)

    if member.evaluator
      instance_exec(**, &member.evaluator)
    else
      object.public_send(member.name)
    end
  end

  def evaluate?(name)
    member = self.class.members.fetch(name)

    result = if member.condition.is_a?(Symbol)
      __send__(member.condition)
    elsif member.condition
      instance_exec(&member.condition)
    else
      true
    end

    !!result
  end
end
