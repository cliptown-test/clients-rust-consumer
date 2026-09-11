#!/usr/bin/env bash
set -euo pipefail

: "${CLIENTS_DIR:?CLIENTS_DIR is required}"
: "${INTERFACES_DIR:?INTERFACES_DIR is required}"
: "${EXPECTED_CLIENT_SHA:?EXPECTED_CLIENT_SHA is required}"
: "${EXPECTED_INTERFACES_SHA:?EXPECTED_INTERFACES_SHA is required}"
: "${EXPECTED_LIB_SHA:?EXPECTED_LIB_SHA is required}"

actual_client_sha="$(git -C "$CLIENTS_DIR" rev-parse HEAD)"
actual_interfaces_sha="$(git -C "$INTERFACES_DIR" rev-parse HEAD)"
[[ "$actual_client_sha" == "$EXPECTED_CLIENT_SHA" ]]
[[ "$actual_interfaces_sha" == "$EXPECTED_INTERFACES_SHA" ]]

cargo_toml="$CLIENTS_DIR/clients/rust/Cargo.toml"
shared_policy="$CLIENTS_DIR/clients/rust/src/shared_policy.rs"
manifest="$CLIENTS_DIR/.zpkg.toml"

# The client candidate must consume shared policy from the canonical library at
# the reviewed immutable revision rather than re-implementing it locally.
grep -F "rev = \"$EXPECTED_LIB_SHA\"" "$cargo_toml"
grep -F "pub const CLIPTOWN_LIB_REVISION: &str = \"$EXPECTED_LIB_SHA\";" "$shared_policy"
grep -F 'pub use cliptown_lib::' "$shared_policy"

python3 - "$manifest" <<'PY'
import pathlib
import sys
import tomllib

manifest = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest["dependencies"] == {
    "cliptown/cliptown-interfaces": "^0.1.0",
    "cliptown/cliptown-lib": "^0.1.0",
}, manifest["dependencies"]
PY

# The Rust client still has a path dependency on the interfaces checkout, so
# place the exact interfaces source at the sibling path expected by Cargo.
clients_parent="$(dirname "$CLIENTS_DIR")"
expected_sibling="$clients_parent/cliptown-interfaces"
if [[ "$(realpath "$INTERFACES_DIR")" != "$(realpath "$expected_sibling")" ]]; then
  echo "interfaces checkout must be the exact sibling expected by Cargo" >&2
  exit 1
fi

cargo metadata \
  --manifest-path "$cargo_toml" \
  --locked \
  --format-version 1 \
  --no-deps >/dev/null
cargo test \
  --manifest-path "$cargo_toml" \
  --locked \
  --all-targets
