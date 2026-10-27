# frozen_string_literal: true

module Enumancer
  module Value
    def type = self.class.enum_type
    def tag = self.class.variant_name
    def to_sym = tag
    def to_s = tag.to_s

    def match(&block)
      type.match(self, &block)
    end

    def deconstruct_keys(keys)
      fields = super(keys&.reject { |key| key == :tag })
      keys.nil? || keys.include?(:tag) ? fields.merge(tag: tag) : fields
    end

    def to_json(*args)
      Serialization.dump(self).to_json(*args)
    end
  end

  private_constant :Value
end
