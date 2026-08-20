# frozen_string_literal: true

# Which resources a named param belongs to when the resource it is asked of is a
# collection serving several types, paired with the members of each.
#
# Only a relationship resolves to a path of its own per type, so only it is
# followed into every type declaring it. Anything else names the collection
# itself and belongs to one resource — whichever declares it.
#
#   call([PostResource, CommentResource], 'tags')     both, each declaring it
#   call([PostResource, CommentResource], 'post-author')  the one that has it
#   call([PostResource, CommentResource], 'id')       one, since it names no path
class OmniSerializer::Jsonapi::CollectionBranches
  extend Dry::Initializer

  option :key_formatter, OmniSerializer::Types::Interface(:call)
  option :type_extractor, OmniSerializer::Types::Interface(:call)
  option :relationship_resolver, OmniSerializer::Types::Interface(:call)

  def call(resource_classes, name)
    indexed = resource_classes.to_h { |resource_class| [resource_class, members(resource_class)] }
    declaring = indexed.select { |resource_class, _| relationship?(resource_class, name) }
    return declaring if declaring.any?

    key, = type_extractor.call(name)
    indexed.slice(indexed.keys.find { |resource_class| indexed[resource_class].key?(key) } || indexed.keys.first)
  end

  private

  def members(resource_class)
    resource_class.members.values.index_by { |member| key_formatter.call(member.name) }
  end

  def relationship?(resource_class, name)
    return relationship_resolver.call(resource_class, name).present? if name.include?('.')

    members(resource_class)[type_extractor.call(name).first].is_a?(OmniSerializer::Resource::Association)
  end
end
