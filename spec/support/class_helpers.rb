# frozen_string_literal: true

module ClassHelpers
  def stub_class(name = nil, superclass = nil, &)
    klass = superclass ? Class.new(superclass, &) : Class.new(&)
    name.present? ? stub_const(name.to_s.camelize, klass) : klass
  end
end
