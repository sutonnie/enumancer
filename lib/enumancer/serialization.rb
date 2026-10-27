# frozen_string_literal: true

module Enumancer
  module Serialization
    def self.dump(value, visiting = {}.compare_by_identity)
      with_visit(value, visiting) do
        data = { name: value.tag }
        if value.type.backed?
          data[:value] = encode(value.value, visiting)
        elsif !value.members.empty?
          data[:fields] = value.to_h.transform_values { |field| encode(field, visiting) }
        end
        data
      end
    end

    def self.encode(value, visiting = {}.compare_by_identity)
      case value
      when Value then dump(value, visiting)
      when Array
        with_visit(value, visiting) { value.map { |item| encode(item, visiting) } }
      when Hash
        with_visit(value, visiting) { value.transform_values { |item| encode(item, visiting) } }
      when String, Symbol, Integer, Float, TrueClass, FalseClass, NilClass then value
      else
        raise TypeError, "Unsupported JSON value: #{value.class}"
      end
    end

    def self.with_visit(value, visiting)
      raise ArgumentError, 'Circular JSON value' if visiting.key?(value)

      visiting[value] = true
      begin
        yield
      ensure
        visiting.delete(value)
      end
    end

    def self.load(type, data)
      raise ArgumentError, 'Expected a JSON object' unless data.is_a?(Hash)
      raise ArgumentError, "Missing 'name' in JSON" unless data['name'].is_a?(String)

      name = Names.normalize(data['name'])
      schema = type.send(:definition_for, name)
      allowed = ['name']
      allowed << 'value' if type.backed?
      allowed << 'fields' unless schema.fields.empty?
      unknown = data.keys - allowed
      raise ArgumentError, "Unknown JSON keys: #{unknown.join(', ')}" unless unknown.empty?

      if type.backed?
        instance = type[name]
        if data.key?('value') && !JSON.parse(JSON.generate(encode(instance.value))).eql?(data['value'])
          raise ArgumentError, 'The backing value does not match the variant'
        end
        return instance
      end

      attributes = data.fetch('fields', {})
      raise ArgumentError, "Expected a JSON object for 'fields'" unless attributes.is_a?(Hash)

      decoded = attributes.to_h do |field, value|
        key = Names.normalize(field)
        constraint = schema.fields[key]
        [key, decode(constraint, value)]
      end
      type[name, **decoded]
    end

    def self.decode(constraint, value)
      if constraint.is_a?(Type)
        load(constraint, value)
      elsif constraint.equal?(Symbol) && value.is_a?(String)
        value.to_sym
      else
        value
      end
    end
  end

  private_constant :Serialization
end
