# frozen_string_literal: true

require 'rspec'
require_relative '../lib/enumancer'

RSpec.describe Enumancer do
  let(:color) do
    Enumancer.define do
      variant :red
      variant :green
      variant :blue
    end
  end

  let(:status) do
    Enumancer.define(backing: Integer) do
      variant :draft, 0
      variant :published, 1
    end
  end

  let(:result) do
    Enumancer.define do
      variant :pending
      variant :ok, value: Integer
      variant :error, message: String
    end
  end

  let(:expression) do
    Enumancer.define do
      variant :number, value: Integer
      variant :add, left: Enumancer::Self, right: Enumancer::Self
    end
  end

  describe '.define' do
    it 'requires a block and at least one variant' do
      expect { Enumancer.define }.to raise_error(ArgumentError)
      expect { Enumancer.define {} }.to raise_error(Enumancer::DefinitionError)
    end

    it 'normalizes string names' do
      type = Enumancer.define { variant 'red' }
      expect(type.red.tag).to eq(:red)
    end

    it 'rejects duplicate normalized names' do
      expect do
        Enumancer.define do
          variant :red
          variant 'red'
        end
      end.to raise_error(Enumancer::DefinitionError, /Duplicate variant/)
    end

    it 'rejects invalid names' do
      expect { Enumancer.define { variant 1 } }.to raise_error(TypeError)
      ['Red', 'red?', 'red-green', '', 'two words'].each do |name|
        expect { Enumancer.define { variant name } }.to raise_error(Enumancer::DefinitionError)
      end
    end

    it 'protects public and private type methods from constructors' do
      [:all, :variants, :match, :matcher, :name, :freeze, :install, :initialize].each do |name|
        expect { Enumancer.define { variant name } }.to raise_error(Enumancer::DefinitionError, /Reserved/)
      end
    end

    it 'rejects colliding generated constants' do
      expect do
        Enumancer.define do
          variant :a1
          variant :a_1
        end
      end.to raise_error(Enumancer::DefinitionError, /constant/)
    end

    it 'requires a class or module for backing and field constraints' do
      expect { Enumancer.define(backing: nil) { variant :none, nil } }.to raise_error(TypeError)
      expect { Enumancer.define { variant :ok, value: 42 } }.to raise_error(Enumancer::DefinitionError)
    end

    it 'rejects positional values without a backing type' do
      expect { Enumancer.define { variant :red, 1 } }.to raise_error(Enumancer::DefinitionError)
    end

    it 'protects value methods from fields' do
      [:tag, :type, :match, :class, :hash, :to_h, :deconstruct_keys, :initialize].each do |field|
        expect do
          Enumancer.define { variant :ok, **{ field => Integer } }
        end.to raise_error(Enumancer::DefinitionError, /Reserved fields/)
      end
    end
  end

  describe 'field names' do
    it 'normalizes strings and rejects duplicate normalized fields' do
      type = Enumancer.define { variant :ok, **{ 'value' => Integer } }
      expect(type.ok(value: 42).value).to eq(42)
      expect do
        Enumancer.define { variant :ok, **{ 'value' => Integer, value: Integer } }
      end.to raise_error(Enumancer::DefinitionError, /Duplicate field/)
    end

    it 'rejects invalid field identifiers' do
      expect do
        Enumancer.define { variant :ok, **{ 'invalid field' => Integer } }
      end.to raise_error(Enumancer::DefinitionError, /Invalid field/)
    end
  end

  describe 'plain enums' do
    it 'returns canonical instances through all public constructors' do
      expect(color.red).to equal(color.red)
      expect(color[:red]).to equal(color.red)
      expect(color['red']).to equal(color.red)
      expect(color::Red.new).to equal(color.red)
      expect(color::Red[]).to equal(color.red)
      expect(color.red.with).to equal(color.red)
    end

    it 'stores no payload fields or per-instance metadata' do
      expect(color.red.members).to eq([])
      expect(color.red.instance_variables).to eq([])
      expect(color.red).not_to respond_to(:value)
    end

    it 'exposes the tag and owning type' do
      expect(color.red.tag).to eq(:red)
      expect(color.red.to_sym).to eq(:red)
      expect(color.red.to_s).to eq('red')
      expect(color.red.type).to equal(color)
    end

    it 'enumerates variants and singleton values in definition order' do
      expect(color.variants).to eq([:red, :green, :blue])
      expect(color.all).to eq([color.red, color.green, color.blue])
    end

    it 'distinguishes variants and separately defined types' do
      other = Enumancer.define { variant :red }
      expect(color.red).not_to eq(color.green)
      expect(color.red).not_to eq(other.red)
      expect(color.red.eql?(other.red)).to be(false)
      expect({ color.red => 'red' }[color[:red]]).to eq('red')
    end

    it 'checks exact membership across all variants' do
      family = color
      impostor = Class.new { include family }.new
      expect(color === color.red).to be(true)
      expect(color === color.blue).to be(true)
      expect(color === result.pending).to be(false)
      expect(color === nil).to be(false)
      expect(color === impostor).to be(false)
    end

    it 'rejects fields on nullary constructors' do
      expect { color.red(value: 1) }.to raise_error(ArgumentError)
      expect { color::Red.new(1) }.to raise_error(ArgumentError)
      expect { color::Red[value: 1] }.to raise_error(ArgumentError)
    end

    it 'raises for unknown variants' do
      expect { color[:missing] }.to raise_error(Enumancer::UnknownVariantError)
      expect { color.missing }.to raise_error(NoMethodError)
    end

    it 'does not provide backing operations' do
      expect(color.backed?).to be(false)
      expect { color.values }.to raise_error(TypeError)
      expect { color.from_value(1) }.to raise_error(TypeError)
    end
  end

  describe 'backed enums' do
    it 'exposes fixed backing values without payload fields' do
      expect(status.backed?).to be(true)
      expect(status.draft.value).to eq(0)
      expect(status.draft.members).to eq([])
      expect(status.values).to eq([0, 1])
    end

    it 'resolves canonical instances by value' do
      expect(status.from_value(1)).to equal(status.published)
      expect { status.from_value(2) }.to raise_error(KeyError)
      expect { status.from_value(1.0) }.to raise_error(KeyError)
    end

    it 'requires exactly one backing value and no fields' do
      expect { Enumancer.define(backing: Integer) { variant :missing } }.to raise_error(Enumancer::DefinitionError)
      expect { Enumancer.define(backing: Integer) { variant :many, 1, 2 } }.to raise_error(Enumancer::DefinitionError)
      expect { Enumancer.define(backing: Integer) { variant :one, 1, extra: String } }.to raise_error(Enumancer::DefinitionError)
    end

    it 'checks backing types and uniqueness' do
      expect { Enumancer.define(backing: Integer) { variant :one, '1' } }.to raise_error(TypeError)
      expect do
        Enumancer.define(backing: Integer) do
          variant :one, 1
          variant :another, 1
        end
      end.to raise_error(Enumancer::DefinitionError, /Duplicate backing/)
    end

    it 'supports nil and false as real backing values' do
      null = Enumancer.define(backing: NilClass) { variant :none, nil }
      boolean = Enumancer.define(backing: FalseClass) { variant :off, false }
      expect(null.from_value(nil)).to equal(null.none)
      expect(boolean.from_value(false)).to equal(boolean.off)
    end

    it 'distinguishes numeric values using hash equality' do
      type = Enumancer.define(backing: Numeric) do
        variant :integer, 1
        variant :float, 1.0
      end
      expect(type.from_value(1)).to equal(type.integer)
      expect(type.from_value(1.0)).to equal(type.float)
      expect(type.integer.eql?(type.float)).to be(false)
    end

    it 'copies strings without freezing the caller value' do
      raw = String.new('draft')
      type = Enumancer.define(backing: String) { variant :draft, raw }
      raw.replace('changed')
      expect(type.draft.value).to eq('draft')
      expect(type.draft.value).to be_frozen
      expect(type.from_value('draft')).to equal(type.draft)
      expect(raw).not_to be_frozen
    end

    it 'copies nested arrays and hashes for stable reverse lookup' do
      raw = [{ String.new('key') => [String.new('value')] }]
      type = Enumancer.define(backing: Array) { variant :config, raw }
      raw.first['key'] << 'changed'
      expect(type.config.value).to eq([{ 'key' => ['value'] }])
      expect(type.config.value.first['key'].first).to be_frozen
      expect(type.from_value([{ 'key' => ['value'] }])).to equal(type.config)
    end

    it 'rejects cyclic backing values' do
      raw = []
      raw << raw
      expect { Enumancer.define(backing: Array) { variant :cycle, raw } }.to raise_error(Enumancer::DefinitionError, /cycles/)
    end

    it 'requires custom backing values to be frozen' do
      raw = Object.new
      expect { Enumancer.define(backing: Object) { variant :custom, raw } }.to raise_error(Enumancer::DefinitionError, /frozen/)
      raw.freeze
      type = Enumancer.define(backing: Object) { variant :custom, raw }
      expect(type.from_value(raw)).to equal(type.custom)
    end
  end

  describe 'algebraic data types' do
    it 'constructs records with named fields' do
      expect(result.ok(value: 42).value).to eq(42)
      expect(result.error(message: 'failure').message).to eq('failure')
      expect(result[:ok, value: 42]).to eq(result.ok(value: 42))
    end

    it 'creates fresh records for variants with fields' do
      expect(result.ok(value: 42)).not_to equal(result.ok(value: 42))
      expect(result.pending).to equal(result.pending)
    end

    it 'rejects missing, unknown, and incorrectly typed fields' do
      expect { result.ok }.to raise_error(ArgumentError, /Missing fields: value/)
      expect { result.ok(value: 42, extra: 1) }.to raise_error(ArgumentError, /Unknown fields: extra/)
      expect { result.ok(value: '42') }.to raise_error(TypeError, /value/)
      expect { result.ok(value: nil) }.to raise_error(TypeError)
    end

    it 'validates all Data construction paths' do
      instance = result.ok(value: 42)
      expect { result::Ok.new(value: 'wrong') }.to raise_error(TypeError)
      expect { result::Ok[value: 'wrong'] }.to raise_error(TypeError)
      expect { instance.with(value: 'wrong') }.to raise_error(TypeError)
      expect(instance.with(value: 43)).to eq(result.ok(value: 43))
    end

    it 'uses consistent Data equality and hashing' do
      first = result.ok(value: 42)
      second = result.ok(value: 42)
      expect(first).to eq(second)
      expect(first.eql?(second)).to be(true)
      expect(first.hash).to eq(second.hash)
      expect({ first => :found }[second]).to eq(:found)
    end

    it 'keeps numeric equality separate from hash equality' do
      type = Enumancer.define { variant :number, value: Numeric }
      expect(type.number(value: 1)).to eq(type.number(value: 1.0))
      expect(type.number(value: 1).eql?(type.number(value: 1.0))).to be(false)
    end

    it 'freezes records without modifying caller payloads' do
      message = String.new('failure')
      instance = result.error(message: message)
      expect(instance).to be_frozen
      expect(instance.message).to equal(message)
      expect(message).not_to be_frozen
      expect { instance.instance_variable_set(:@extra, 1) }.to raise_error(FrozenError)
    end

    it 'supports module and generated type constraints' do
      marker = Module.new
      inner = color
      object = Object.new.extend(marker)
      type = Enumancer.define { variant :item, value: marker, color: inner }
      expect(type.item(value: object, color: color.red).value).to equal(object)
      expect { type.item(value: Object.new, color: color.red) }.to raise_error(TypeError)
      expect { type.item(value: object, color: result.pending) }.to raise_error(TypeError)
    end

    it 'exposes variants without trying to enumerate all possible records' do
      expect(result.variants).to eq([:pending, :ok, :error])
      expect { result.all }.to raise_error(TypeError, /variants/)
    end

    it 'supports native hash patterns with tags' do
      matched = case result.ok(value: 42)
                in { tag: :ok, value: Integer => number } then number
                else nil
                end
      expect(matched).to eq(42)
      expect(result.ok(value: 42).deconstruct_keys([:value])).to eq(value: 42)
    end

    it 'supports native class patterns' do
      stub_const('PatternResult', result)
      matched = case PatternResult.ok(value: 42)
                in PatternResult::Ok(value:) then value
                else nil
                end
      expect(matched).to eq(42)
    end
  end

  describe 'recursive types' do
    it 'resolves Self to the completed type' do
      tree = expression.add(left: expression.number(value: 1), right: expression.number(value: 2))
      expect(tree.left.type).to equal(expression)
      expect(expression === tree).to be(true)
      expect do
        expression.add(left: tree, right: result.pending)
      end.to raise_error(TypeError, /right/)
    end

    it 'supports reusable recursive matchers' do
      evaluate = expression.matcher do
        on(:number) { |number| number.value }
        on(:add) { |add| evaluate.call(add.left) + evaluate.call(add.right) }
      end
      tree = expression.add(left: expression.number(value: 2), right: expression.number(value: 3))
      expect(evaluate.call(tree)).to eq(5)
    end
  end

  describe 'exhaustive matching' do
    it 'dispatches through an instance match' do
      output = result.ok(value: 42).match do
        on(:pending) { 'pending' }
        on(:ok) { |ok| ok.value.to_s }
        on(:error) { |error| error.message }
      end
      expect(output).to eq('42')
    end

    it 'supports type-level matching' do
      output = color.match(color.red) do
        on(:red) { 1 }
        on(:green) { 2 }
        on(:blue) { 3 }
      end
      expect(output).to eq(1)
    end

    it 'passes the whole variant object to the handler' do
      instance = result.ok(value: 42)
      output = instance.match do
        on(:pending) { nil }
        on(:ok) { |value| value }
        on(:error) { nil }
      end
      expect(output).to equal(instance)
    end

    it 'runs exactly one handler after collecting all branches' do
      calls = []
      result.pending.match do
        on(:pending) { calls << :pending }
        on(:ok) { calls << :ok }
        on(:error) { calls << :error }
        calls << :defined
      end
      expect(calls).to eq([:defined, :pending])
    end

    it 'checks missing branches before running a covered handler' do
      calls = []
      expect do
        result.pending.match do
          on(:pending) { calls << :pending }
          on(:ok) { calls << :ok }
        end
      end.to raise_error(Enumancer::NonExhaustiveMatchError, /error/)
      expect(calls).to eq([])
    end

    it 'reports every missing branch at matcher construction' do
      expect do
        result.matcher { on(:pending) {} }
      end.to raise_error(Enumancer::NonExhaustiveMatchError, /ok, error/)
    end

    it 'rejects duplicate normalized branches before dispatch' do
      expect do
        result.pending.match do
          on(:pending) { raise 'must not execute' }
          on('pending') {}
        end
      end.to raise_error(Enumancer::DuplicateBranchError, /pending/)
    end

    it 'rejects unknown branches and missing handlers' do
      expect { result.matcher { on(:unknown) {} } }.to raise_error(Enumancer::UnknownVariantError)
      expect { result.matcher { on(:pending) } }.to raise_error(Enumancer::MatchError, /handler/)
    end

    it 'requires a match block' do
      expect { result.matcher }.to raise_error(Enumancer::MatchError)
      expect { result.pending.match }.to raise_error(Enumancer::MatchError)
    end

    it 'reuses a frozen matcher across variants' do
      matcher = result.matcher do
        on(:pending) { :pending }
        on(:ok) { |ok| ok.value }
        on(:error) { |error| error.message }
      end
      expect(matcher.call(result.pending)).to eq(:pending)
      expect(matcher.call(result.ok(value: 42))).to eq(42)
      expect(matcher.call(result.error(message: 'failure'))).to eq('failure')
      expect(matcher).to be_frozen
    end

    it 'rejects foreign values even with identical tags' do
      matcher = color.matcher do
        on(:red) { raise 'must not execute' }
        on(:green) {}
        on(:blue) {}
      end
      other = Enumancer.define { variant :red }
      [other.red, nil, :red].each do |value|
        expect { matcher.call(value) }.to raise_error(TypeError)
      end
    end

    it 'propagates handler errors without trying another branch' do
      matcher = color.matcher do
        on(:red) { raise 'handler failure' }
        on(:green) { raise 'wrong branch' }
        on(:blue) { raise 'wrong branch' }
      end
      expect { matcher.call(color.red) }.to raise_error(RuntimeError, 'handler failure')
    end

    it 'returns nil and false normally' do
      matcher = color.matcher do
        on(:red) { nil }
        on(:green) { false }
        on(:blue) { true }
      end
      expect(matcher.call(color.red)).to be_nil
      expect(matcher.call(color.green)).to be(false)
    end

    it 'prevents changing compiled handlers through an escaped builder' do
      builder = nil
      matcher = color.matcher do
        builder = self
        on(:red) { 1 }
        on(:green) { 2 }
        on(:blue) { 3 }
      end
      expect { builder.on(:red) { 9 } }.to raise_error(Enumancer::DuplicateBranchError)
      expect(matcher.call(color.red)).to eq(1)
    end
  end

  describe 'closed definitions' do
    it 'freezes types, classes, names, and enumerations' do
      [color, color::Red, color.variants, color.all, status.values].each do |object|
        expect(object).to be_frozen
      end
    end

    it 'prevents extending the variant set' do
      expect { color.const_set(:Yellow, Class.new) }.to raise_error(FrozenError)
      expect { color.define_singleton_method(:yellow) {} }.to raise_error(FrozenError)
      expect { color.variants << :yellow }.to raise_error(FrozenError)
      expect(color).not_to respond_to(:variant)
      expect(color).not_to respond_to(:remove)
    end

    it 'prevents subclassing variants and unchecked allocation' do
      expect { Class.new(result::Ok) }.to raise_error(TypeError, /subclassed/)
      expect { result::Ok.allocate }.to raise_error(NoMethodError)
    end

    it 'closes escaped definition builders' do
      builder = nil
      Enumancer.define do
        builder = self
        variant :red
      end
      expect { builder.variant(:green) }.to raise_error(FrozenError)
    end

    it 'prevents copying a type with constructors owned by the original' do
      expect { color.dup }.to raise_error(TypeError, /copied/)
      expect { color.clone }.to raise_error(TypeError, /copied/)
    end
  end

  describe 'JSON' do
    it 'round trips plain enums as canonical instances' do
      expect(JSON.parse(color.red.to_json)).to eq('name' => 'red')
      expect(color.from_json(color.red.to_json)).to equal(color.red)
    end

    it 'round trips backed enums and accepts name-only input' do
      expect(JSON.parse(status.draft.to_json)).to eq('name' => 'draft', 'value' => 0)
      expect(status.from_json(status.draft.to_json)).to equal(status.draft)
      expect(status.from_json('{"name":"draft"}')).to equal(status.draft)
    end

    it 'rejects inconsistent backing values, including numeric types' do
      expect { status.from_json('{"name":"draft","value":1}') }.to raise_error(ArgumentError)
      expect { status.from_json('{"name":"draft","value":0.0}') }.to raise_error(ArgumentError)
    end

    it 'round trips symbol, nil, and false backing values' do
      type = Enumancer.define(backing: Object) do
        variant :draft, :draft
        variant :none, nil
        variant :off, false
      end
      type.all.each { |value| expect(type.from_json(value.to_json)).to equal(value) }
    end

    it 'round trips ADT records and nullary variants' do
      instance = result.ok(value: 42)
      expect(JSON.parse(instance.to_json)).to eq('name' => 'ok', 'fields' => { 'value' => 42 })
      expect(result.from_json(instance.to_json)).to eq(instance)
      expect(result.from_json(result.pending.to_json)).to equal(result.pending)
    end

    it 'supports JSON.generate on nested enum values' do
      data = JSON.parse(JSON.generate([color.red, result.ok(value: 42)]))
      expect(data).to eq([{ 'name' => 'red' }, { 'name' => 'ok', 'fields' => { 'value' => 42 } }])
    end

    it 'round trips recursive types' do
      tree = expression.add(left: expression.number(value: 1), right: expression.number(value: 2))
      expect(expression.from_json(tree.to_json)).to eq(tree)
    end

    it 'round trips fields constrained to another generated type' do
      inner = color
      outer = Enumancer.define { variant :paint, color: inner }
      instance = outer.paint(color: color.red)
      expect(outer.from_json(instance.to_json)).to eq(instance)
    end

    it 'restores fields declared as Symbol' do
      type = Enumancer.define { variant :item, key: Symbol }
      expect(type.from_json(type.item(key: :hello).to_json)).to eq(type.item(key: :hello))
    end

    it 'validates deserialized fields' do
      expect { result.from_json('{"name":"ok","fields":{"value":"42"}}') }.to raise_error(TypeError)
      expect { result.from_json('{"name":"ok"}') }.to raise_error(ArgumentError, /Missing fields/)
      expect do
        result.from_json('{"name":"ok","fields":{"value":42,"extra":1}}')
      end.to raise_error(ArgumentError, /Unknown fields/)
    end

    it 'rejects unknown variants' do
      expect { color.from_json('{"name":"unknown"}') }.to raise_error(Enumancer::UnknownVariantError)
    end

    it 'rejects missing and invalid names' do
      ['{}', '{"name":null}', '{"name":42}', '{"name":false}'].each do |json|
        expect { color.from_json(json) }.to raise_error(ArgumentError)
      end
    end

    it 'rejects non-object and malformed documents' do
      ['null', '[]', '42', '"red"'].each do |json|
        expect { color.from_json(json) }.to raise_error(ArgumentError)
      end
      expect { color.from_json('{') }.to raise_error(JSON::ParserError)
    end

    it 'rejects unknown envelope keys and fields on unit variants' do
      expect { color.from_json('{"name":"red","extra":1}') }.to raise_error(ArgumentError)
      expect { color.from_json('{"name":"red","fields":{}}') }.to raise_error(ArgumentError)
    end

    it 'requires an object for ADT fields' do
      expect { result.from_json('{"name":"ok","fields":null}') }.to raise_error(ArgumentError)
      expect { result.from_json('{"name":"ok","fields":[]}') }.to raise_error(ArgumentError)
    end

    it 'rejects circular payloads without overflowing the stack' do
      type = Enumancer.define { variant :items, values: Array }
      values = []
      instance = type.items(values: values)
      values << instance
      expect { instance.to_json }.to raise_error(ArgumentError, /Circular JSON/)
    end

    it 'allows repeated references that do not form a cycle' do
      type = Enumancer.define { variant :items, values: Array }
      repeated = [1, 2]
      instance = type.items(values: [repeated, repeated])
      expect(type.from_json(instance.to_json)).to eq(instance)
    end

    it 'rejects unsupported custom JSON values' do
      type = Enumancer.define { variant :custom, value: Object }
      expect { type.custom(value: Object.new).to_json }.to raise_error(TypeError, /Unsupported JSON/)
    end
  end
end
