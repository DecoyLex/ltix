# Versioning

Ltix follows [Semantic Versioning](https://semver.org/). Its public API is every documented module, function, type, callback, and option in the `ltix` package.

## Before 1.0

A minor release may make breaking changes. The changelog and an upgrading guide describe each one. A patch release makes no breaking changes.

## After 1.0

Minor and patch releases keep the public API compatible. A breaking change ships behind a compatibility flag in a minor release, or in the next major release.

### Compatibility flags

Each compatibility flag is a boolean key under `config :ltix` that turns on one new behavior. A flag you haven't set keeps the old behavior, and Ltix logs a warning at startup that names it. Setting the flag to `true` or `false` removes the warning.

`mix igniter.install ltix` sets every flag to `true` in a new project. `mix igniter.upgrade` leaves your flags as they are.

The next major release makes each flag's new behavior the default and removes the flag.

## Security fixes

A fix that makes Ltix behave as its docs or the LTI specification it implements describe is a bug fix. It ships in a patch release and is on by default, even when your tool can observe the change.

Hardening beyond what the docs and the specifications require ships behind a compatibility flag, with a security advisory. The next major release makes it the default.

## New specifications and platform extensions

After 1.0, support for a new LTI specification starts as a separate package at 0.x. It moves into `ltix` in a minor release once it reaches 1.0.

Extensions for one platform, such as Canvas, ship as separate packages.

## Dependencies

Ltix's version requirement on a dependency below 1.0 accepts the dependency's later 0.x releases.

## Major releases

Ltix makes a major release for a new major version of LTI, or to make the behavior of its compatibility flags the default once they accumulate.

After a major release, the previous major version gets security fixes for 12 months.
