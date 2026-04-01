# Unit Testing

PPUX includes a small Jest-like test framework built on top of LÖVE.

## Running unit tests

From the repo root:

```bash
./scripts/unix/run_unit_tests.sh
```

On Windows:

```bat
scripts\windows\run_unit_tests.bat
```

Or manually:

```bash
cd test
love .
```

The runner opens a LÖVE window and shows passing tests, failing tests, and error details.

## Where unit tests live

- test files: `test/tests/unit/*.test.lua`
- runner entrypoint: `test/main.lua`

`test/main.lua` loads each test file explicitly, so new test files must also be added there.

## Test structure

Available globals:

- `describe(name, fn)`
- `it(name, fn)`
- `beforeEach(fn)`
- `afterEach(fn)`
- `expect(value)`

Common matchers:

- `toBe`
- `toEqual`
- `toBeNil`
- `toBeTruthy`
- `toBeFalsy`
- `toThrow`
- `toBeGreaterThan`
- `toBeGreaterThanOrEqual`
- `toBeLessThan`
- `toNotBe`

Example:

```lua
local TableUtils = require("utils.table_utils")

describe("table_utils.lua", function()
  it("clones flat arrays", function()
    local out = TableUtils.clone({ 1, 2, 3 })
    expect(out).toEqual({ 1, 2, 3 })
  end)
end)
```

## Adding a new unit test

1. Create a file under `test/tests/unit/`.
2. Write `describe(...)` / `it(...)` blocks.
3. Add it to `test/main.lua`.
4. Run `./scripts/unix/run_unit_tests.sh` (or `scripts\windows\run_unit_tests.bat`).

## Good patterns

- keep tests small and focused
- prefer controller or module-level tests
- stub only what the test needs
- reuse `beforeEach` / `afterEach` for repeated setup

## Useful examples

- `test/tests/unit/taskbar_minimize.test.lua`
- `test/tests/unit/keyboard_input.test.lua`
- `test/tests/unit/chr_backing_integration.test.lua`
