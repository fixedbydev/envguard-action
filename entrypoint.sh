#!/bin/sh
set -e

# ── inputs ──────────────────────────────────────────────
ENV_FILE="${INPUT_ENV_FILE:-.env.example}"
SCHEMA="${INPUT_SCHEMA:-}"
EXAMPLE_FILE="${INPUT_EXAMPLE_FILE:-}"
FORMAT="${INPUT_FORMAT:-github}"
FAIL_ON="${INPUT_FAIL_ON:-undeclared,missing}"
WORKING_DIR="${INPUT_WORKING_DIRECTORY:-.}"
SRC_DIR="${INPUT_SRC_DIR:-./src}"

cd "$WORKING_DIR"

EXIT_CODE=0
UNDECLARED="[]"
MISSING="[]"
UNUSED="[]"

# ── helper: emit GitHub annotation ──────────────────────
annotate() {
  local level="$1" # error or warning
  local key="$2"
  local msg="$3"
  echo "::${level}::${key}: ${msg}"
}

# ── 1. diff check (env-file vs example-file) ───────────
if [ -n "$EXAMPLE_FILE" ] && [ -f "$EXAMPLE_FILE" ]; then
  echo "::group::Diff: $ENV_FILE vs $EXAMPLE_FILE"

  # Extract keys from both files
  env_keys=""
  if [ -f "$ENV_FILE" ]; then
    env_keys=$(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | cut -d= -f1 | sort)
  fi
  example_keys=$(grep -v '^\s*#' "$EXAMPLE_FILE" | grep -v '^\s*$' | cut -d= -f1 | sort)

  # Missing: in example but not in env
  diff_missing=$(comm -23 <(echo "$example_keys") <(echo "$env_keys") 2>/dev/null || true)
  if [ -n "$diff_missing" ]; then
    MISSING_JSON="["
    first=true
    for key in $diff_missing; do
      if [ "$first" = true ]; then first=false; else MISSING_JSON="${MISSING_JSON},"; fi
      MISSING_JSON="${MISSING_JSON}\"${key}\""
      annotate "error" "$key" "Missing from $ENV_FILE (present in $EXAMPLE_FILE)"
    done
    MISSING_JSON="${MISSING_JSON}]"
    MISSING="$MISSING_JSON"

    if echo "$FAIL_ON" | grep -q "missing"; then
      EXIT_CODE=1
    fi
  fi

  echo "::endgroup::"
fi

# ── 2. schema audit (if schema provided) ───────────────
if [ -n "$SCHEMA" ] && [ -f "$SCHEMA" ]; then
  echo "::group::Audit: process.env usage vs schema"

  AUDIT_OUTPUT=$(env-guard audit --dir "$SRC_DIR" --schema "$SCHEMA" --json 2>/dev/null || true)

  if [ -n "$AUDIT_OUTPUT" ]; then
    # Extract undeclared keys
    AUDIT_UNDECLARED=$(echo "$AUDIT_OUTPUT" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
      console.log(JSON.stringify(data.undeclared.map(u => u.key)));
    " 2>/dev/null || echo "[]")

    AUDIT_UNUSED=$(echo "$AUDIT_OUTPUT" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
      console.log(JSON.stringify(data.unused));
    " 2>/dev/null || echo "[]")

    AUDIT_UNSAFE=$(echo "$AUDIT_OUTPUT" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
      console.log(JSON.stringify(data.unsafe.map(u => u.expression)));
    " 2>/dev/null || echo "[]")

    # Emit annotations for undeclared
    echo "$AUDIT_OUTPUT" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
      for (const u of data.undeclared) {
        console.log('::error file=' + u.file + ',line=' + u.line + '::UNDECLARED env var \"' + u.key + '\" is not in the schema');
      }
      for (const u of data.unsafe) {
        console.log('::warning file=' + u.file + ',line=' + u.line + '::DYNAMIC_ACCESS process.env[' + u.expression + '] cannot be statically verified');
      }
      for (const k of data.unused) {
        console.log('::warning::UNUSED schema key \"' + k + '\" is never referenced in code');
      }
    " 2>/dev/null || true

    UNDECLARED="$AUDIT_UNDECLARED"

    # Merge unused into output
    if [ "$AUDIT_UNUSED" != "[]" ]; then
      UNUSED="$AUDIT_UNUSED"
    fi

    # Check fail conditions
    if echo "$FAIL_ON" | grep -q "undeclared"; then
      if [ "$AUDIT_UNDECLARED" != "[]" ]; then
        EXIT_CODE=1
      fi
    fi

    if echo "$FAIL_ON" | grep -q "unused"; then
      if [ "$AUDIT_UNUSED" != "[]" ]; then
        EXIT_CODE=1
      fi
    fi

    if echo "$FAIL_ON" | grep -q "unsafe"; then
      if [ "$AUDIT_UNSAFE" != "[]" ]; then
        EXIT_CODE=1
      fi
    fi

    # Summary
    echo "$AUDIT_OUTPUT" | node -e "
      const data = JSON.parse(require('fs').readFileSync('/dev/stdin','utf-8'));
      console.log('Audit: ' + data.summary.undeclared + ' undeclared, ' + data.summary.unused + ' unused, ' + data.summary.unsafe + ' dynamic');
    " 2>/dev/null || true
  fi

  echo "::endgroup::"
fi

# ── 3. env file key check (without schema) ─────────────
if [ -z "$SCHEMA" ] && [ -z "$EXAMPLE_FILE" ] && [ -f "$ENV_FILE" ]; then
  echo "::group::Check: $ENV_FILE"

  # Check for empty values
  empty_keys=$(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | grep '=$' | cut -d= -f1 || true)
  if [ -n "$empty_keys" ]; then
    for key in $empty_keys; do
      annotate "warning" "$key" "Empty value in $ENV_FILE"
    done
  fi

  echo "Checked $(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | wc -l | tr -d ' ') keys in $ENV_FILE"
  echo "::endgroup::"
fi

# ── 4. set outputs ─────────────────────────────────────
VALID="true"
if [ "$EXIT_CODE" -ne 0 ]; then
  VALID="false"
fi

if [ -n "$GITHUB_OUTPUT" ]; then
  echo "valid=${VALID}" >> "$GITHUB_OUTPUT"
  echo "undeclared=${UNDECLARED}" >> "$GITHUB_OUTPUT"
  echo "missing=${MISSING}" >> "$GITHUB_OUTPUT"
  echo "unused=${UNUSED}" >> "$GITHUB_OUTPUT"
fi

# ── summary ─────────────────────────────────────────────
if [ "$VALID" = "true" ]; then
  echo ""
  echo "✅ EnvGuard: All checks passed"
else
  echo ""
  echo "❌ EnvGuard: Validation failed"
fi

exit $EXIT_CODE
