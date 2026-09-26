import Lake
open Lake DSL

package connectrpc where
  version := v!"0.1.0"
  description := "Connect RPC for Lean 4: the Connect, gRPC and gRPC-Web protocols over HTTP/1.1 and HTTP/2"
  license := "Apache-2.0"
  keywords := #["rpc", "connect", "grpc", "grpc-web", "protobuf", "http"]

-- Message types, the binary wire format and ProtoJSON come from Lean-zh/protobuf,
-- the way connect-go builds on google.golang.org/protobuf.
require protobuf from git "https://github.com/Lean-zh/protobuf.git" @ "v0.4.0"

/-- The runtime: protocols, codecs, compression, server and client. -/
@[default_target]
lean_lib Connect

/-- The service stub generator, shared by the protoc plugin. -/
lean_lib ConnectGen where
  globs := #[.submodules `ConnectGen]

/-- `protoc-gen-connect-lean`: generates service stubs next to the messages
    that `protoc-gen-lean4` generates. -/
@[default_target]
lean_exe «protoc-gen-connect-lean» where
  root := `ConnectGen.Main

lean_lib Tests where
  srcDir := "tests"
  globs := #[.submodules `Tests]

lean_exe tests where
  srcDir := "tests"
  root := `Main

/-- Builds and runs the tests, and compiles the README's code. -/
@[test_driver]
script test do
  let build ← IO.Process.spawn { cmd := "lake", args := #["build", "tests", "ReadmeCheck"] }
  let code ← build.wait
  if code != 0 then return code
  let run ← IO.Process.spawn { cmd := "lake", args := #["exe", "tests"] }
  run.wait

/-! ## Examples -/

lean_lib ElizaGen where
  srcDir := "examples/eliza"
  globs := #[.submodules `ElizaGen]

lean_lib Eliza where
  srcDir := "examples/eliza"
  globs := #[.submodules `Eliza]

lean_exe «eliza-server» where
  srcDir := "examples/eliza"
  root := `ElizaServer

lean_exe «eliza-client» where
  srcDir := "examples/eliza"
  root := `ElizaClient

/-! ## Conformance (connectrpc/conformance) -/

lean_lib ConformanceGen where
  srcDir := "conformance"
  globs := #[.submodules `ConformanceGen]

lean_lib Conformance where
  srcDir := "conformance"
  globs := #[.submodules `Conformance]

lean_exe «conformance-server» where
  srcDir := "conformance"
  root := `ConformanceServer

lean_exe «conformance-client» where
  srcDir := "conformance"
  root := `ConformanceClient

/-- The code shown in README.md, compiled to keep it honest. -/
lean_lib ReadmeCheck where
  srcDir := "examples/readme"

/-- Code generated from tests/proto: names that collide or are keywords. -/
lean_lib EdgeGen where
  srcDir := "tests"
  globs := #[.submodules `EdgeGen]

lean_exe bench where
  srcDir := "examples/bench"
  root := `Bench
