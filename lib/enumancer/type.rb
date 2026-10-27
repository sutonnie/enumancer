# frozen_string_literal: true

module Enumancer
  class Type < Module
    attr_reader :variants

    def initialize(definitions, backing:)
      super()
      @backing_type = backing
      @definitions = {}
      @classes = {}
      @class_names = {}.compare_by_identity
      @singletons = {}
      @value_index = {}
      include Value

      definitions.each { |definition| install(definition) }
      @variants = @definitions.keys.freeze
      [@definitions, @classes, @class_names, @singletons, @value_index].each(&:freeze)
      freeze
    end

    def backed? = !@backing_type.equal?(UNSET)

    def ===(value)
      @class_names.key?(value.class)
    end

    def [](name, **attributes)
      name = Names.normalize(name)
      definition_for(name)
      @classes.fetch(name).new(**attributes)
    end

    def all
      unless @singletons.length == @definitions.length
        raise TypeError, 'Types with fields cannot enumerate all values; use variants'
      end

      @singletons.values.freeze
    end

    def values
      raise TypeError, 'This type has no backing values' unless backed?

      @definitions.values.map(&:backing).freeze
    end

    def from_value(value)
      raise TypeError, 'This type has no backing values' unless backed?

      @value_index.fetch(value) { raise KeyError, "Unknown backing value: #{value.inspect}" }
    end

    def matcher(&block)
      Matcher.new(self, &block)
    end

    def match(value, &block)
      matcher(&block).call(value)
    end

    def from_json(json)
      Serialization.load(self, JSON.parse(json))
    end

    private

    def initialize_copy(_other)
      raise TypeError, 'Enumancer types cannot be copied'
    end

    def definition_for(name)
      @definitions.fetch(name) { raise UnknownVariantError, "Unknown variant: #{name}" }
    end

    def install(definition)
      name = definition.name
      raise DefinitionError, "Reserved variant name: #{name}" if respond_to?(name, true)

      constant = name.to_s.split('_').map(&:capitalize).join
      raise DefinitionError, "Duplicate variant constant: #{constant}" if const_defined?(constant, false)

      fields = definition.fields.transform_values { |constraint| constraint.equal?(Self) ? self : constraint }.freeze
      reserved = fields.keys & (Data.instance_methods + Data.private_instance_methods + Value.instance_methods)
      raise DefinitionError, "Reserved fields: #{reserved.join(', ')}" unless reserved.empty?

      backing = prepare_backing(definition.backing) if backed?
      definition = Definition.new(name, fields, backing)
      klass = build_class(definition)
      @definitions[name] = definition
      @classes[name] = klass
      @class_names[klass] = name
      const_set(constant, klass)

      if fields.empty?
        instance = klass.new
        @singletons[name] = instance
        @value_index[backing] = instance if backed?
        constructor = lambda do |*args, **attributes|
          unless args.empty? && attributes.empty?
            raise ArgumentError, "#{name} does not accept fields"
          end

          instance
        end
        klass.define_singleton_method(:new, &constructor)
        klass.define_singleton_method(:[], &constructor)
      end

      define_singleton_method(name) { |**attributes| self[name, **attributes] }
      klass.freeze
    end

    def prepare_backing(value)
      unless @backing_type === value
        raise TypeError, "Expected backing type #{@backing_type}, got #{value.class}"
      end

      snapshot = BackingSnapshot.copy(value)
      raise DefinitionError, "Duplicate backing value: #{value.inspect}" if @value_index.key?(snapshot)

      snapshot
    end

    def build_class(definition)
      owner = self
      fields = definition.fields
      klass = Data.define(*fields.keys) do
        include owner

        define_method(:initialize) do |**attributes|
          missing = fields.keys - attributes.keys
          unknown = attributes.keys - fields.keys
          raise ArgumentError, "Missing fields: #{missing.join(', ')}" unless missing.empty?
          raise ArgumentError, "Unknown fields: #{unknown.join(', ')}" unless unknown.empty?

          fields.each do |field, constraint|
            unless constraint === attributes[field]
              raise TypeError, "Invalid type for #{field}: expected #{constraint}, got #{attributes[field].class}"
            end
          end
          super(**attributes)
        end
      end
      klass.define_singleton_method(:enum_type) { owner }
      klass.define_singleton_method(:variant_name) { definition.name }
      klass.define_singleton_method(:inherited) { |_child| raise TypeError, 'Variants cannot be subclassed' }
      klass.define_method(:value) { definition.backing } if backed?
      klass.private_class_method(:allocate)
      klass
    end
  end
end
