# Chess project guidelines

## Language

All code artifacts must be written in English: `@moduledoc`, `@doc`, inline comments, section headers (`##`), test descriptions (`describe`, `test`), and variable/function names.

## Development workflow: TDD and baby steps

All new features must be developed using Test-Driven Development (TDD) in small, incremental steps:

1. **Red** — write the smallest possible failing test that describes the next behavior.
2. **Green** — write the minimum production code needed to make that test pass. Do not write more than required.
3. **Refactor** — clean up code without changing behavior; all tests must remain green.

Repeat this cycle for each new behavior. Never write production code before a failing test exists for it.
