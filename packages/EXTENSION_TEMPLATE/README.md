# Extension Template

A starter template for creating new Autopoiesis extensions.

## Quick Start

1. Copy this directory:
   ```bash
   cp -r packages/EXTENSION_TEMPLATE packages/my-extension
   ```

2. Rename the `.asd` file and update all references:
   ```bash
   cd packages/my-extension
   mv extension-template.asd my-extension.asd
   # Then find-replace "extension-template" -> "my-extension" in all files
   ```

3. Implement your extension in `src/`

4. Write tests in `test/`

5. Test it:
   ```lisp
   (ql:quickload :autopoiesis/my-extension)
   (asdf:test-system :autopoiesis/my-extension)
   ```

## Structure

```
my-extension/
  my-extension.asd      # ASDF system definition
  src/
    packages.lisp        # Package definition with exports
    my-extension.lisp    # Implementation
  test/
    my-extension-tests.lisp
  README.md
```

## Available APIs

Your extension depends on `:autopoiesis` which gives you access to:

- **Substrate** (`autopoiesis.substrate`): Datom store, Linda coordination, entity types
- **Core** (`autopoiesis.core`): S-expressions, cognitive primitives, persistent data structures
- **Agent** (`autopoiesis.agent`): Agent runtime, capabilities, persistent agents
- **Snapshot** (`autopoiesis.snapshot`): Content-addressable storage, branching, time-travel
- **Integration** (`autopoiesis.integration`): LLM providers, tool registry, MCP
- **Orchestration** (`autopoiesis.orchestration`): Conductor, event queue

If you only need the datom store, depend on `:substrate` instead of `:autopoiesis`.
