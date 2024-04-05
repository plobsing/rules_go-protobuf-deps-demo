# Go + build-time protobuf example

This repo contains two Go modules:
* `github.com/example/project/go` under `go/`
* `github.com/example/project/proto` under `proto/`

The Go sources for the `proto/` module are not checked in; they're generated as part of the build.

Pinning dependencies is managed by the `./go/pin_deps.sh` script, which updates both trees' module lockfiles at the same time.
