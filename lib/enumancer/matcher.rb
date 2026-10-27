# frozen_string_literal: true

module Enumancer
  class MatchBuilder
    def initialize(names)
      @names = names
      @handlers = {}
    end

    def on(name, &handler)
      name = Names.normalize(name)
      raise UnknownVariantError, "Unknown variant: #{name}" unless @names.include?(name)
      raise DuplicateBranchError, "Duplicate branch: #{name}" if @handlers.key?(name)
      raise MatchError, "A handler is required for #{name}" unless handler

      @handlers[name] = handler
      nil
    end

    def finish
      missing = @names - @handlers.keys
      unless missing.empty?
        raise NonExhaustiveMatchError, "Missing branches: #{missing.join(', ')}"
      end

      @handlers.freeze
      freeze
      @handlers
    end
  end

  class Matcher
    def initialize(type, &block)
      raise MatchError, 'A match block is required' unless block

      @type = type
      builder = MatchBuilder.new(type.variants)
      builder.instance_eval(&block)
      @handlers = builder.finish
      freeze
    end

    def call(value)
      raise TypeError, 'The value does not belong to this type' unless @type === value

      @handlers.fetch(value.tag).call(value)
    end
  end

  private_constant :MatchBuilder
end
