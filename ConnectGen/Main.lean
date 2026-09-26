module

public import ConnectGen.Emit
public import ConnectGen.Proto.google.protobuf.compiler.plugin

public section

/-!
# `protoc-gen-connect-lean`

A `protoc` plugin. For every input file that declares services, it writes
`<file>_connect.lean` next to the `<file>.lean` that `protoc-gen-lean4`
produces, and imports it.

Options, comma-separated in `--connect-lean_opt` (or `opt:` in `buf.gen.yaml`):

* `lean4_prefix=<Module.Prefix>`: the prefix given to `protoc-gen-lean4`, so the
  generated imports find the message modules;
* `no_server`, `no_client`: leave out the server or client half.
-/

namespace ConnectGen

open google.protobuf
open google.protobuf.compiler

private def str (s : Protobuf.UnvalidatedString) : String := s.toString?.getD ""

/-- Plugin options. -/
structure PluginOptions where
  leanPrefix : String := ""
  emit : Options := {}

def parseOptions (param : String) : Except String PluginOptions := do
  let mut o : PluginOptions := {}
  for part in param.splitOn "," do
    let part := part.trimAscii.toString
    if part.isEmpty then continue
    match part.splitOn "=" with
    | ["lean4_prefix", v] => o := { o with leanPrefix := v }
    | ["runtime_module", v] => o := { o with emit.runtimeModule := v }
    | ["no_server"] => o := { o with emit.server := false }
    | ["no_client"] => o := { o with emit.client := false }
    | _ => throw s!"unknown option {part.quote}"
  return o

/-- The Lean module `protoc-gen-lean4` writes for a proto file. -/
def moduleFor (leanPrefix : String) (protoPath : String) : String :=
  if protoPath == "google/protobuf/descriptor.proto" then "Protobuf.Internal.Desc"
  else
    let stem := if protoPath.endsWith ".proto" then (protoPath.dropEnd 6).toString else protoPath
    let parts := (stem.splitOn "/").map escapeComponent
    let prefixParts := (leanPrefix.splitOn ".").filter (!·.isEmpty) |>.map escapeComponent
    ".".intercalate (prefixParts ++ parts)

/-- Path of the generated file for a proto file. -/
def outputPath (protoPath : String) : String :=
  let stem := if protoPath.endsWith ".proto" then (protoPath.dropEnd 6).toString else protoPath
  stem ++ "_connect.lean"

/-- Maps every message's full name (no leading dot) to the file declaring it. -/
private def messageFiles (files : Array FileDescriptorProto) : Std.HashMap String String := Id.run do
  let mut out : Std.HashMap String String := {}
  for f in files do
    let fileName := f.name.getD ""
    let pkg := f.package.getD ""
    let rec walk (fuel : Nat) (scope : String) (msgs : Array DescriptorProto)
        (acc : Std.HashMap String String) : Std.HashMap String String :=
      match fuel with
      | 0 => acc
      | fuel + 1 => msgs.foldl (init := acc) fun acc m =>
        let full := if scope.isEmpty then m.name.getD "" else scope ++ "." ++ m.name.getD ""
        walk fuel full m.nested_type (acc.insert full fileName)
    out := walk 64 pkg f.message_type out
  return out

private def commentAt (f : FileDescriptorProto) (path : Array Int32) : Option String := do
  let info ← f.source_code_info
  let loc ← info.location.find? (·.path == path)
  let c ← loc.leading_comments
  if c.trimAscii.isEmpty then none else some c

private def stripDot (s : String) : String :=
  if s.startsWith "." then (s.drop 1).toString else s

/-- Describes the services of one proto file. -/
def fileInfo (opts : PluginOptions) (files : Std.HashMap String String)
    (f : FileDescriptorProto) : FileInfo := Id.run do
  let path := f.name.getD ""
  let mut services := #[]
  let mut importFiles : Array String := #[path]
  for svc in f.service, si in [0:f.service.size] do
    let mut methods := #[]
    for m in svc.method, mi in [0:svc.method.size] do
      let input := stripDot (m.input_type.getD "")
      let output := stripDot (m.output_type.getD "")
      for t in [input, output] do
        if let some file := files[t]? then
          unless importFiles.contains file do importFiles := importFiles.push file
      let streaming := match m.client_streaming.getD false, m.server_streaming.getD false with
        | false, false => Streaming.unary
        | true, false => .clientStream
        | false, true => .serverStream
        | true, true => .bidiStream
      let idempotency := match m.options.bind (·.idempotency_level) with
        | some .NO_SIDE_EFFECTS => Idempotency.noSideEffects
        | some .IDEMPOTENT => .idempotent
        | _ => .unknown
      methods := methods.push {
        name := m.name.getD "", inputType := input, outputType := output, streaming, idempotency
        deprecated := (m.options.bind (·.deprecated)).getD false
        comment := commentAt f #[6, si.toInt32, 2, mi.toInt32] }
    services := services.push {
      name := svc.name.getD "", methods
      deprecated := (svc.options.bind (·.deprecated)).getD false
      comment := commentAt f #[6, si.toInt32] }
  return {
    protoPath := path, package := f.package.getD "", services
    imports := importFiles.map (moduleFor opts.leanPrefix) }

private def response (files : Array CodeGeneratorResponse.File := #[])
    (error : Option String := none) : CodeGeneratorResponse := {
  error := error.map Protobuf.UnvalidatedString.ofString
  file := files
  supported_features := some 3
  minimum_edition := some (1000 : Int32)
  maximum_edition := some (1001 : Int32) }

/-- Runs the plugin on a decoded request. -/
def generate (req : CodeGeneratorRequest) : CodeGeneratorResponse := Id.run do
  let opts ← match parseOptions (str (req.parameter.getD .empty)) with
    | .ok o => o
    | .error e => return response (error := some e)
  let files := messageFiles req.proto_file
  let mut out := #[]
  for target in req.file_to_generate do
    let target := str target
    let some f := req.proto_file.find? (·.name == some target)
      | return response (error := some s!"{target} is missing from the request")
    if let some content := emitFile opts.emit (fileInfo opts files f) then
      out := out.push { name := some (.ofString (outputPath target)), content := some (.ofString content) }
  return response out

end ConnectGen

open ConnectGen in
public def main : IO UInt32 := do
  let input ← (← IO.getStdin).readBinToEnd
  let req ← match Protobuf.decodeThe google.protobuf.compiler.CodeGeneratorRequest input with
    | .ok r => pure r
    | .error _ =>
      IO.eprintln "protoc-gen-connect-lean: could not parse the request from protoc"
      return 1
  match Protobuf.encode (generate req) with
  | .ok bytes =>
    let out ← IO.getStdout
    out.write bytes
    out.flush
    return 0
  | .error _ =>
    IO.eprintln "protoc-gen-connect-lean: could not encode the response"
    return 1
