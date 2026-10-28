# frozen_string_literal: true

module Enumancer
  module Names
    def self.normalize(name)
      unless name.is_a?(String) || name.is_a?(Symbol)
        raise TypeError, 'Names must be strings or symbols'
      end

      name.to_sym
    end
  end

  Definition = Data.define(:name, :fields, :backing)

  class DefinitionBuilder
    def initialize(backing:)
      @backed = backing
      @definitions = {}
    end

    def variant(name, *values, **fields)
      name = Names.normalize(name)
      raise DefinitionError, "Duplicate variant: #{name}" if @definitions.key?(name)

      if @backed
        raise DefinitionError, 'Backed variants require exactly one value' unless values.length == 1
        raise DefinitionError, 'Backed variants cannot have fields' unless fields.empty?
      elsif !values.empty?
        raise DefinitionError, 'Backing values require a backing type'
      end

      normalized = {}
      fields.each do |field, constraint|
        field = Names.normalize(field)
        raise DefinitionError, "Duplicate field: #{field}" if normalized.key?(field)

        unless constraint.is_a?(Module) || constraint.equal?(Self)
          raise DefinitionError, "Invalid type for field #{field}: #{constraint.inspect}"
        end
        normalized[field] = constraint
      end

      @definitions[name] = Definition.new(name, normalized.freeze, values.first)
      nil
    end

    def finish
      raise DefinitionError, 'At least one variant is required' if @definitions.empty?

      @definitions.freeze
      freeze
      @definitions.values.freeze
    end
  end

  module BackingSnapshot
    def self.copy(value, visiting = {}.compare_by_identity)
      raise DefinitionError, 'Backing values cannot contain cycles' if visiting.key?(value)

      visiting[value] = true
      case value
      when String
        value.dup.freeze
      when Array
        value.dup.map! { |item| copy(item, visiting) }.freeze
      when Hash
        value.each_with_object(value.dup.clear) do |(key, item), result|
          result[copy(key, visiting)] = copy(item, visiting)
        end.freeze
      else
        raise DefinitionError, 'Custom backing values must be frozen' unless value.frozen?

        value
      end
    ensure
      visiting.delete(value)
    end
  end

  private_constant :Names, :Definition, :DefinitionBuilder, :BackingSnapshot
end
