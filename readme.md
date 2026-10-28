# Enumancer

[![Gem Version](https://img.shields.io/gem/v/enumancer?include_prereleases&logo=rubygems&logoColor=%23e0e0e0&label=version&labelColor=%23FF748C&color=pink&style=for-the-badge)](https://rubygems.org/gems/enumancer)

Closed enums and algebraic data types for **Ruby 4.0+**, with typed fields and
exhaustive matching. No runtime dependencies outside the Ruby standard library.

## Installation

```ruby
gem 'enumancer', '~> 2.0'
```

```sh
bundle install
```

## Plain enums

```ruby
require 'enumancer'

Color = Enumancer.define do
  variant :red
  variant :green
  variant :blue
end

Color.red.equal?(Color[:red]) # => true
Color.red.tag                # => :red
Color.red.to_sym             # => :red
Color.red.to_s               # => "red"
Color.red.type               # => Color
Color === Color.red          # => true
Color.variants               # => [:red, :green, :blue]
Color.all                    # => [Color.red, Color.green, Color.blue]
```

Each variant has its own generated `Data` class, such as `Color::Red`.
Variants without fields return canonical frozen instances and store no payload
or tag fields in those instances. Plain enum instances have no `value` method.

Names can be symbols or strings; there is no naming-style validation. Case is
preserved, including camelCase and PascalCase. Generated class constants uppercase
the first letter of each underscore-separated part: `lParen` becomes `LParen`,
and `http_error` becomes `HttpError`. Ruby's rules for generated methods and
constants still apply. Names that conflict with existing type or instance methods,
or produce duplicate class constants, are rejected during definition.

## Backed enums

```ruby
Status = Enumancer.define(backing: Integer) do
  variant :draft, 0
  variant :published, 1
end

Status.draft.value   # => 0
Status.from_value(1) # => Status.published
Status.values        # => [0, 1]
Status.backed?       # => true
```

Every variant must have exactly one unique backing value matching the declared
class or module. Backed variants cannot have payload fields. `nil` is a backing
value when the declared type accepts it; it does not mean an omitted value.

Reverse lookup uses `eql?` and `hash`, so `1` and `1.0` are distinct backing
values. Unknown values raise `KeyError`.

Strings, arrays, and hashes used as backing values are copied and recursively
frozen without freezing the caller's objects. Cyclic backing values are rejected.
Custom backing objects must already be frozen; their nested state must remain
stable for reverse lookup.

## Algebraic data types

```ruby
Result = Enumancer.define do
  variant :pending
  variant :ok, value: Integer
  variant :error, message: String
end

result = Result.ok(value: 42)
result.value                  # => 42
result.tag                    # => :ok
Result[:error, message: 'Failed'].message # => "Failed"
Result.variants               # => [:pending, :ok, :error]
```

Field constraints accept classes, modules, and other Enumancer types. All fields
are required. Missing and unknown fields raise `ArgumentError`; invalid values
raise `TypeError`. Checks also apply to generated class constructors and `with`:

```ruby
result.with(value: 43)         # => Result.ok(value: 43)
Result::Ok.new(value: 'wrong') # raises TypeError
```

Records use `Data` equality and hashing: equal records must have the same variant
class and equal fields. Types with fields cannot enumerate every possible value;
use `variants` instead of `all`.

Records are shallowly immutable, following Ruby's `Data` semantics. Nested
payload objects remain shared with the caller. Freeze or copy mutable payloads
before using records as hash keys.

## Exhaustive matching

```ruby
result.match do
  on(:pending) { 'Waiting' }
  on(:ok)      { |ok| ok.value.to_s }
  on(:error)   { |error| error.message }
end
```

Each handler receives the entire variant instance. The selected handler's return
value becomes the match result, including `nil` and `false`.

The outer block runs in a branch-builder context. It collects handlers without
executing them. Every variant must be covered exactly once before any handler
runs:

- Missing branches raise `Enumancer::NonExhaustiveMatchError`.
- Duplicate branches raise `Enumancer::DuplicateBranchError`.
- Unknown variants raise `Enumancer::UnknownVariantError`.
- Missing handler blocks raise `Enumancer::MatchError`.

There is no wildcard branch. Completeness is checked at runtime against the
closed definition, including when the current value belongs to a covered branch.
Handler exceptions propagate normally.

For reuse, build a matcher once. Completeness is checked when it is built:

```ruby
render = Result.matcher do
  on(:pending) { 'Waiting' }
  on(:ok)      { |ok| ok.value.to_s }
  on(:error)   { |error| error.message }
end

render.call(Result.ok(value: 42)) # => "42"
```

`Result.match(result) { ... }` also supports direct type-level dispatch.
Passing a value from another type to a matcher raises `TypeError`.

## Recursive types

```ruby
Expr = Enumancer.define do
  variant :number, value: Integer
  variant :add, left: Enumancer::Self, right: Enumancer::Self
end

evaluate = Expr.matcher do
  on(:number) { |number| number.value }
  on(:add)    { |add| evaluate.call(add.left) + evaluate.call(add.right) }
end

tree = Expr.add(left: Expr.number(value: 2), right: Expr.number(value: 3))
evaluate.call(tree) # => 5
```

`Enumancer::Self` resolves to the type being defined. Recursive fields reject
values from other types.

## Native Ruby patterns

Generated classes also support native patterns:

```ruby
case result
in Result::Ok(value:)
  puts value
in { tag: :error, message: }
  warn message
end
```

`deconstruct_keys` exposes payload fields and `tag`. Use Enumancer's `match`
when every variant must have a handler.

## JSON

```ruby
Color.red.to_json
# => '{"name":"red"}'

Status.draft.to_json
# => '{"name":"draft","value":0}'

Result.ok(value: 42).to_json
# => '{"name":"ok","fields":{"value":42}}'

Result.from_json('{"name":"ok","fields":{"value":42}}')
# => Result.ok(value: 42)
```

Deserialization validates variant names, envelope keys, field names, and field
types. Plain and backed enums return their canonical instances. Backed input
may omit `value`; if present, it must match the named variant's JSON value.

Fields explicitly constrained to another Enumancer type, including `Self`, are
decoded recursively. Fields declared as `Symbol` are restored from JSON strings.
Unparameterized `Array`, `Hash`, and `Object` fields follow ordinary JSON
semantics: collection element types, symbol keys, and nested enum identities
cannot be inferred from those constraints. Custom objects require conversion to
supported JSON values; arbitrary classes are not instantiated by deserialization.
Circular payloads are rejected.

## Closed definitions

After the definition block finishes, the type, variant classes, and registry are
frozen. Variants cannot be added, removed, or subclassed. Unknown names raise
`Enumancer::UnknownVariantError`; there is no `:unknown` fallback. Type objects
cannot be copied.

## Migrating from 1.x

Version 2 intentionally breaks compatibility with the inheritance API:

```ruby
Status = Enumancer.define(backing: Integer) do
  variant :draft, 0
  variant :published, 1
end
```

Replace `class Status < Enumancer::Enum` with the factory, `type Integer` with
`backing: Integer`, and `entry` with `variant`. Remove `strict:` options: names
and types are always checked. Replace `name_for(value)` with
`from_value(value).tag`, and `keys` with `variants`. Runtime registration,
`remove`, unregistered instances, and inheritance are no longer supported.

## Development

```sh
bundle install
bundle exec rspec
gem build enumancer.gemspec
```
