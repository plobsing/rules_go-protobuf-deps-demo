#!/usr/bin/env bash
#
# Regenerate the listing of third-party deps of protobuf-generates Go sources.
# The listing is maintained for the benefit of Gazelle.

# shellcheck disable=SC1090  # ShellCheck cannot analyze Bazel runfiles lib incantation (its too dynamic).

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
	source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
	source "$0.runfiles/$f" 2>/dev/null ||
	source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
	source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
	{
		echo >&2 "ERROR: cannot find $f"
		exit 1
	}
f=
set -e
# --- end runfiles.bash initialization v3 ---

set -euo pipefail

scratch_dir="$(mktemp -d)"
function cleanup() {
	rm -rf "$scratch_dir"
}
trap cleanup EXIT

cd "$BUILD_WORKSPACE_DIRECTORY"

# Generate all Go sources.
bazel build --output_groups=go_generated_srcs //proto/... --build_event_json_file="${scratch_dir}/bep.json"

# Enumerate all packages imported by the generated Go sources.
jq --raw-output 'select(.id.namedSet.id != null) | .namedSetOfFiles.files[].uri | ltrimstr("file://")' <"${scratch_dir}/bep.json" |
	xargs "$(rlocation example/go/protodeps/list_imports_/list_imports)" |
	cut -d' ' -f2 |
	sort -u >"${scratch_dir}/imported.txt"

# Elide imports of first-party code (i.e. other protos from our repo).
grep -v '^github\.com/example/project/proto' <"${scratch_dir}/imported.txt" >"${scratch_dir}/third_party.txt"

# Emit blank-imports for all third-party dependencies of the generated code.
readonly pkgname="protodeps"
"$(rlocation example/go/protodeps/blank_import_/blank_import)" "$pkgname" <"${scratch_dir}/third_party.txt" >"${BUILD_WORKSPACE_DIRECTORY}/go/protodeps/protodeps.go"
