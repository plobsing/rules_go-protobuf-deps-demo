#!/usr/bin/env bash
#
# Pin external dependencies using the Go module system's lockfiles.
#
# //go:go.mod and //go:go.sum are updated to reflect the current external dependencies of the Go source tree under //go.
# These go module lockfile are mapped into Bazel via Gazelle and
#
# Special attention is paid to the tree of generated Go sources under //proto.
# It is adapted so that Go tooling does not complain about its absence.
# In addition, its dependencies are ensured by mirroring them to the //go/protodeps package.
#
# The Go module lockfile are mapped into Bazel via Gazelle's Bzlmod API in //:MODULE.bazel.

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

# Set up just enough of a module for our protos that tools acting against the Go source tree will cope with our generated sources.
proto_scratch_dir="${scratch_dir}/proto"
proto_gen_go_symtree "${proto_scratch_dir}"
(
	cd "${proto_scratch_dir}"
	go mod init "github.com/example/project/proto"
)

# Ensure the mirroring of protobuf gencode deps into our Go source tree is kept up to date.
# This mirroring is necessary to ensure that generated code dependencies are available through Bazel.
bazel run //go/protodeps:update

# Shim the local, ephemeral github.com/example/project/proto module into the github.com/example/project/go module before tidying the latter.
(
	cd "${srctree_root}/go"
	go mod edit --replace github.com/example/project/proto="${proto_scratch_dir}"
	trap "go mod edit --dropreplace github.com/example/project/proto --droprequire github.com/example/project/proto" EXIT
	go mod tidy
)

# Tidy MODULE.bazel in order to update our `use_repo` of Gazelle's `go_deps` extension to the latest set of imported libraries.
bazel mod tidy
