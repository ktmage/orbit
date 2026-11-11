# Orbit

English | [日本語](README.ja.md)

[![CI](https://github.com/ktmage/orbit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ktmage/orbit/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) ![Status: Experimental](https://img.shields.io/badge/Status-Experimental-orange.svg)

Orbit is a plugin framework that implements Cordis's Context Paradigm in MoonBit. Plugins register operations and their cleanup with a context, and Orbit starts and stops them according to their declared dependencies.

> [!WARNING]
> Orbit is experimental. Features and documentation may be incomplete. API stability, security, and continued maintenance are not guaranteed.

A service is a function or value that a plugin exposes to other plugins. Orbit waits until the required services are available before starting a plugin. When a service provider's configuration or implementation changes, Orbit also stops and restarts the plugins that depend on it.

As a MoonBit counterpart to Cordis, Orbit adopts the [paper's](https://arxiv.org/pdf/2608.25512v1) ideas of revertible effects, reactive dependencies, and composition through contexts. API compatibility is outside its scope. Orbit is independent of any particular application and can be embedded in command-line tools, desktop applications, and other hosts.

## Features

- Register the same plugin multiple times, each with its own configuration and state.
- Identify services with typed keys and access functions or values provided by other plugins.
- Group nested operations with `ctx.with_effect` and dispose of that group independently with `EffectHandle.dispose()`. Tasks, resources, subscriptions, and child plugins are cleaned up together.
- Group lifetimes with `scope.child()` and isolate service resolution for individual keys with `scope.isolate(key.realm())`. Sibling scopes can share a provider by using the same realm.
- Supply service metadata with `scope.intercept`. Services can also use `ServiceContext.effect` to bind their own operations to the caller's lifetime.
- Dispatch events sequentially or in parallel. Other modes support stopping dispatch early or letting each handler invoke the next one.
- Request cancellation of asynchronous work, such as network operations, when a plugin stops. Wait for that work to finish and for cleanup, such as closing files, to complete.
- Retry failed cleanup from the point of failure. Completed cleanup is not repeated, and the pending configuration update or removal can resume.
- Pass a declarative configuration to the loader to apply changes using stable entry IDs. Unchanged instances keep running, and a failed update triggers an attempt to restore the previous configuration.
- Inspect plugin state, selected service providers, errors, and the results of configuration changes.

The host implements code loading through `Resolver`. `Loader.reload` prepares all definitions before replacing running plugins and preserves the current configuration if loading fails. File watching and loaders for arbitrary JavaScript or Wasm binaries are not included.

Service authors are responsible for ensuring that cleanup reverses an operation's changes and that independent operations can be reordered without changing the result. Orbit retains and executes the cleanup functions. It does not automatically undo data already sent externally or changes to shared state outside its control. For events where order matters, priorities and instance registration order are preserved across restarts.

## Supported targets

Orbit supports compilation to JavaScript and WebAssembly. JavaScript tests run on Node.js, and WebAssembly tests run on MoonBit's `moonrun`.

## Development setup

[mise.toml](mise.toml) specifies the versions and installation methods for MoonBit, Node.js, Python, and other tools. This configuration and CI target macOS on Apple Silicon.

With [mise](https://mise.jdx.dev/getting-started.html) installed, clone the repository and prepare the development environment:

```sh
git clone git@github.com:ktmage/orbit.git
cd orbit
mise trust
mise install
mise exec -- moon update
```

## Running the examples

The [clock service example](examples/clock/main.mbt) registers one plugin that provides a time value and another that prints it to the terminal.

```sh
mise exec -- moon run examples/clock --target js
mise exec -- moon run examples/clock --target wasm
```

Both commands print:

```text
12:00
13:00
```

The display plugin can be registered first: it waits until the clock service is available. Registering the clock produces `12:00`; updating its configuration restarts the plugins and produces `13:00`. The example then shuts down all registered plugins.

See the example's [moon.pkg](examples/clock/moon.pkg) for the required package imports. Import `Runtime`, which manages plugin registration and shutdown, from `core/runtime`, and `ServiceKey`, which identifies services, from `core/service`. The `adapters/async_driver` package uses MoonBit task groups to start and cancel asynchronous work requested by Orbit.

The [revision update example](examples/reload/main.mbt) keeps plugins running when the same configuration is reapplied and updates the service and its consumer only when the revision changes. Its Resolver selects from prepared definitions to demonstrate the same update flow on JavaScript and Wasm.

```sh
mise exec -- moon run examples/reload --target js
mise exec -- moon run examples/reload --target wasm
```

Both commands print two lines: `v1` and `v2`. The [command registry](extensions/commands/commands.mbt) demonstrates an extension that uses the service API to register operations and removes them when the consumer stops, without changes to Orbit's core.

`child()` does not isolate service resolution. Migrate code that needs the previous fallback to parent providers to `shadow()`, or use `isolate()` for strict isolation. Use `isolate_events()` to separate event dispatch channels.

## Tests and static checks

Run the following commands from the Orbit repository root. CI uses the same commands.

```sh
mise exec -- python3 tools/check_ci.py --target js
mise exec -- python3 tools/check_ci.py --target wasm
```

[check_ci.py](tools/check_ci.py) checks formatting and workflow syntax, then runs tests for the validation tools themselves. It also checks package dependency directions and runs Orbit's tests and examples on the selected target.

| Tests | What they verify |
| --- | --- |
| Package tests | Individual features return the expected results. |
| [Public API integration tests](tests/integration/) | Registration, configuration changes, shutdown, and other operations work together. |
| [Generated operation sequences](tests/sequences/) | Overlapping updates and removals wait for cleanup to finish and leave unrelated plugins running. |
| [Compile-fail tests](tests/compile_fail/) | The compiler rejects incorrect types and access to private fields. |

The test runner compares the number of planned tests with the number completed. Compile-fail tests first compile a valid example, then check that an invalid example is rejected at the expected location for the expected reason.

[GitHub Actions](.github/workflows/ci.yml) runs these checks on pushes and when pull requests are opened or updated. JavaScript and WebAssembly run in separate jobs, so their results can be inspected independently. Manual runs are also supported.

## Source layout

| Directory | Responsibility |
| --- | --- |
| [loader](loader/) | Apply declarative configuration changes, update revisions, and restore configurations after failures. |
| [extensions/commands](extensions/commands/) | Provide reversible command registration as a service. |
| [core/runtime](core/runtime/) | Accept plugin registrations and changes, and coordinate startup and shutdown. |
| [core/dependency](core/dependency/) | Resolve service providers and determine shutdown order from dependencies. |
| [core/service](core/service/) | Store service values and return typed references. |
| [core/lifecycle](core/lifecycle/) | Request cancellation, wait for asynchronous work to finish, and run cleanup. |
| [core/event](core/event/) | Register event handlers and invoke them using the selected dispatch mode. |
| [core/identity](core/identity/) | Issue identifiers for plugins, operations, and other managed objects. |
| [adapters/async_driver](adapters/async_driver/) | Execute asynchronous work using MoonBit task groups. |

Each package's `pkg.generated.mbti` lists its public types and functions.

The host application implements networking, file operations, and configuration storage. Orbit itself does not send configuration or diagnostic data to external services.

## License

[MIT License](LICENSE). Copyright ktmage.
