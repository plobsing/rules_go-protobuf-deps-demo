# Go + build-time protobuf example

This repo contains two logical Go modules:
* `github.com/example/project/go` under `go/`
* `github.com/example/project/proto` under `proto/`

The Go sources for the `proto/` module are not checked in; they're generated as part of the build. There is no
`go.mod` lockfile for this module; its dependencies are mirrored into `go/protodeps` using the `update.sh` script in
that package.

Pinning dependencies is managed by the `./go/pin_deps.sh` script, which updates `go/protodeps`, `go/go.mod`, and `MODULE.bazel`.
