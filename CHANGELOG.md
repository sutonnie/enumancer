# Changelog

## 2.0.1

- Remove snake_case validation for variant and field names.
- Preserve camelCase, PascalCase, and acronyms in generated variant class names.
- Keep duplicate name, reserved method, and generated constant collision checks.

## 2.0.0

- Require Ruby 4.0 or newer.
- Replace enum inheritance with `Enumancer.define` and automatically closed types.
- Support plain enums, backed enums, and typed algebraic data types through one definition API.
- Generate frozen `Data` classes for variants, with canonical instances for variants without fields.
- Add exhaustive `match` and reusable `matcher` with unknown, duplicate, and missing branch checks before dispatch.
- Add recursive field constraints through `Enumancer::Self`.
- Support native Ruby patterns and JSON serialization, including nested declared types.
- Remove mutable registries, unregistered instances, and non-strict fallbacks.

This release intentionally breaks compatibility with 1.x. Replace subclasses of
`Enumancer::Enum` with `Enumancer.define`, `entry` with `variant`, and
`type Integer` with `backing: Integer`. See the README for examples.
