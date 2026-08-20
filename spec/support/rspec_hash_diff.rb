# frozen_string_literal: true

require 'hashdiff'
require 'rainbow'

class RspecHashDiff
  def format(diff_line)
    case diff_line[0]
    when '~'
      format_replace(diff_line) + yield(diff_line[2], diff_line[3]) unless matches?(diff_line[2], diff_line[3])
    when '-'
      format_removal(diff_line)
    when '+'
      format_addition(diff_line)
    end
  end

  private

  def matches?(expected, actual)
    if expected.respond_to?(:matches?)
      expected.matches?(actual)
    else
      RSpec::Support::FuzzyMatcher.values_match?(expected, actual)
    end
  end

  def format_replace(diff_line)
    "#{Rainbow(diff_line[0]).color(:default)}#{Rainbow(diff_line[1]).color(:default)} ⇒\n"
  end

  def format_removal(diff_line)
    "#{Rainbow(diff_line[0]).red}#{Rainbow(diff_line[1]).red} " \
      "⇒ #{Rainbow(diff_line[2].inspect).lightpink.bg(:red)}"
  end

  def format_addition(diff_line)
    "#{Rainbow(diff_line[0]).green}#{Rainbow(diff_line[1]).green} " \
      "⇒ #{Rainbow(diff_line[2].inspect).lightgreen.bg(:green)}"
  end
end

RSpec::Support::Differ.class_eval do
  def diff_as_object(actual, expected)
    if (actual.is_a?(Hash) && expected.is_a?(Hash)) || (actual.is_a?(Array) && expected.is_a?(Array))
      diff_as_hash(actual, expected)
    else
      diff_as_object_for_expect_matcher(actual, expected)
    end
  end

  def diff_as_object_for_expect_matcher(actual, expected)
    case expected
    when RSpec::Matchers::BuiltIn::Compound::And
      diff_as_compound_and(actual, expected)
    when RSpec::Mocks::ArgumentMatchers::HashIncludingMatcher
      expected = expected.instance_variable_get(:@expected)
      diff_as_object(actual.slice(*expected.keys), expected)
    when RSpec::Matchers::BuiltIn::ContainExactly
      diff_as_object(actual, expected.expected)
    when RSpec::Matchers::BuiltIn::HaveAttributes
      diff_as_object(expected.actual, expected.expected)
    else
      diff_as_string(object_to_string(actual), object_to_string(expected))
    end
  end

  def diff_as_hash(actual, expected)
    formatter = RspecHashDiff.new
    diff = Hashdiff.diff(expected, actual, use_lcs: false).filter_map do |line|
      formatter.format(line) do |exp, act|
        diff_as_object(act, exp)
      end
    end.join("\n")

    "\n#{diff}"
  end

  def diff_as_compound_and(actual, expected)
    [
      (diff_as_object(actual, expected.matcher_1) unless expected.matcher_1.matches?(actual)),
      (diff_as_object(actual, expected.matcher_2) unless expected.matcher_2.matches?(actual))
    ].compact.join("\n")
  end
end
