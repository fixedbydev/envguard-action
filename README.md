# EnvGuard Action

[![Test Action](https://github.com/fixedbydev/envguard-action/actions/workflows/test.yml/badge.svg)](https://github.com/fixedbydev/envguard-action/actions/workflows/test.yml)

GitHub Action that validates environment variables against schemas and `.env.example` files in CI. Produces inline PR annotations for each issue.

## Quick Start

### Validate `.env.example` is complete

```yaml
- name: Check env vars
  uses: fixedbydev/envguard-action@v1
  with:
    env-file: .env.example
    example-file: .env.example.dist
```

### Audit `process.env` usage against schema

```yaml
- name: Audit env usage
  uses: fixedbydev/envguard-action@v1
  with:
    schema: ./env.schema.ts
    src-dir: ./src
    fail-on: undeclared,missing
```

### Block deploy if required keys missing

```yaml
- name: Validate environment
  uses: fixedbydev/envguard-action@v1
  with:
    env-file: .env.production
    example-file: .env.example
    fail-on: missing
```

## Inputs

| Input | Description | Default |
| --- | --- | --- |
| `env-file` | Path to `.env` file to validate | `.env.example` |
| `schema` | Path to `env.schema.ts` for audit | *(optional)* |
| `example-file` | Path to `.env.example` for diff | *(optional)* |
| `format` | Output format: `github`, `json`, `pretty` | `github` |
| `fail-on` | Comma-separated fail conditions: `undeclared`, `missing`, `unused`, `unsafe` | `undeclared,missing` |
| `working-directory` | Working directory (monorepo support) | `.` |
| `src-dir` | Source directory for audit scan | `./src` |

## Outputs

| Output | Description |
| --- | --- |
| `valid` | `true` if all checks passed, `false` otherwise |
| `undeclared` | JSON array of undeclared env var keys |
| `missing` | JSON array of missing env var keys |
| `unused` | JSON array of unused schema keys |

## Usage Examples

### 1. Validate `.env.example` on every PR

```yaml
name: Env Check
on: pull_request

jobs:
  env-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: fixedbydev/envguard-action@v1
        with:
          env-file: .env.example
          example-file: .env.example.dist
```

### 2. Audit `process.env` usage in codebase

```yaml
name: Env Audit
on: [push, pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: fixedbydev/envguard-action@v1
        with:
          schema: ./env.schema.ts
          src-dir: ./src
          fail-on: undeclared
```

### 3. Use outputs in subsequent steps

```yaml
- name: Validate env
  id: envguard
  uses: fixedbydev/envguard-action@v1
  continue-on-error: true
  with:
    env-file: .env.example
    example-file: .env.example.dist

- name: Handle results
  run: |
    echo "Valid: ${{ steps.envguard.outputs.valid }}"
    echo "Missing: ${{ steps.envguard.outputs.missing }}"
```

### 4. Monorepo support

```yaml
- uses: fixedbydev/envguard-action@v1
  with:
    working-directory: ./packages/api
    env-file: .env.example
    schema: ./env.schema.ts
```

## How It Works

1. Runs in a Docker container (Node 20 Alpine)
2. Installs `@stacklance/envguard-cli` and `@stacklance/envguard-audit`
3. Performs diff (`.env` vs `.env.example`) and/or schema audit
4. Emits `::error::` and `::warning::` annotations for GitHub PR integration
5. Sets action outputs via `$GITHUB_OUTPUT`
6. Exits with code 1 if any `fail-on` condition is met

## Local Testing with `act`

```bash
# Install act: https://github.com/nektos/act
act -j test-diff-pass
```

## License

MIT
