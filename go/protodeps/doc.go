// Package protodeps mirrors the external dependencies of Go sources generated from protobufs.
//
// Using blank imports, we are able to ensure the availability of these libraries even
// when these might not be directly imported by any checked-in Go sources; these would otherwise
// be overlooked and elided by Gazelle.
//
// An update script is included to regenerate the dependency set if and when they change.
// Its output is stable; it is safe to re-run the updater script at any time.
// The script should be invoked through Bazel:
//
//	bazel run //go/protodeps:update
package protodeps
