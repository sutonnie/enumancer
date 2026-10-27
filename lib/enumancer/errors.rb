# frozen_string_literal: true

module Enumancer
  class DefinitionError < ArgumentError; end
  class UnknownVariantError < KeyError; end
  class MatchError < ArgumentError; end
  class DuplicateBranchError < MatchError; end
  class NonExhaustiveMatchError < MatchError; end
end
