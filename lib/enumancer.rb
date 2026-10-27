# frozen_string_literal: true

require 'json'
require_relative 'enumancer/errors'
require_relative 'enumancer/definition'
require_relative 'enumancer/matcher'
require_relative 'enumancer/value'
require_relative 'enumancer/serialization'
require_relative 'enumancer/type'

module Enumancer
  Self = Object.new.freeze
  UNSET = Object.new.freeze
  private_constant :UNSET

  def self.define(backing: UNSET, &block)
    raise ArgumentError, 'A definition block is required' unless block
    unless backing.equal?(UNSET) || backing.is_a?(Module)
      raise TypeError, 'The backing type must be a class or module'
    end

    builder = DefinitionBuilder.new(backing: !backing.equal?(UNSET))
    builder.instance_eval(&block)
    Type.new(builder.finish, backing: backing)
  end
end
