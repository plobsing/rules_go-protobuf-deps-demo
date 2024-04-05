#!/usr/bin/env bash

set -euo pipefail

scratch_dir="$(mktemp -d)"
function cleanup() {
	rm -rf "$scratch_dir"
}
trap cleanup EXIT

srctree_root="$(bazel info workspace)"

# Use the go-tool from Bazel's rules_go.
function go() {
	# Capture PWD so we can reestablish once running under `bazel run`.
	# `bazel run` resets PWD to the repo root (https://github.com/bazelbuild/bazel/issues/3325).
	# Also, we can't `bazel run` outside of a repo; we need to `cd` into the monorepo
	# for the build and then jump back to where we started before executing the built binary.
	oldpwd="$(pwd)"
	(
		cd "${srctree_root}"

		# rules_go wrapper honours BUILD_WORKING_DIRECTORY, which would interfere with an ordinary chdir.
		run_under_cmd="export BUILD_WORKING_DIRECTORY='${oldpwd}' && exec"

		bazel run --run_under="$run_under_cmd" @io_bazel_rules_go//go -- "$@"
	)
}

# Build a symlink tree, rooted at $1, to the //proto/... generated Go sources.
function proto_gen_go_symtree() {
	output_root="$1"

	# `bazel cquery --output=files` results are relative to execution_root.
	exec_root="$(bazel info execution_root)"

	bazel build --output_groups=go_generated_srcs //proto/...

	bazel cquery --output=files --output_groups=go_generated_srcs //proto/... |
		while read -r exec_relative; do
			# Path of generated file relative to a the //proto tree root.
			go_path="${exec_relative#*/github.com/example/project/proto}"

			src_path="${exec_root}/${exec_relative}"
			dst_path="${output_root}/${go_path}"

			# The same protobuf source can be used to generate outputs for multiple Bazel configurations.
			# No matter what configuration we're in, this ought to generate the same Go source code.
			# We care that the destination file has the intended content, we don't care if we're the
			# ones that put it there.
			if [[ -e $dst_path ]]; then
				if cmp --silent -- "${src_path}" "${dst_path}"; then
					continue
				else
					echo "Aliasing entries for ${go_path} differ in content." >&2
					exit 1
				fi
			fi

			mkdir -p "$(dirname -- "${dst_path}")"
			ln -s "${src_path}" "${dst_path}"
		done
}

proto_scratch_dir="${scratch_dir}/proto"
proto_gen_go_symtree "${proto_scratch_dir}"

# Use symlinks to map //proto:go.* lockfiles into the generated code tree.
# These symlinks will be written through by `go mod tidy` and `go work sync`,
# updating the lockfiles in the source tree.
ln -s "${srctree_root}/proto/go.mod" "${proto_scratch_dir}/go.mod"
ln -s "${srctree_root}/proto/go.sum" "${proto_scratch_dir}/go.sum"
(
	cd "${proto_scratch_dir}"
	go mod tidy
)

# Shim the local, ephemeral github.com/example/project/proto module into the github.com/example/project/go module and tidy the latter.
# These will be wired together in a workspace, but workspaces and module
# maintenance do not interact conveniently (https://github.com/golang/go/issues/50750).
(
	cd "${srctree_root}/go"
	go mod edit --replace github.com/example/project/proto="${proto_scratch_dir}"
	trap "go mod edit --dropreplace github.com/example/project/proto --droprequire github.com/example/project/proto" EXIT
	go mod tidy
)

# Create an ephemeral go workspace and use it to drive `gazelle update-repos`.
scratch_go_workspace="${scratch_dir}/workspace"
mkdir "${scratch_go_workspace}"
(
	cd "${scratch_go_workspace}"

	go work init \
		"${srctree_root}/go" \
		"${proto_scratch_dir}"

	# Note: `go work sync` only harmonizes dependency versions between a
	# workspace's modules, it does not tidy the individual modules. That must be
	# performed separately (as is done above).
	# See https://github.com/golang/go/issues/50750.
	go work sync
)

bazel run //:gazelle -- \
        update-repos \
        --from_file="${scratch_go_workspace}/go.work" \
        --prune \
        --to_macro="go/repositories.bzl%go_dependencies"
