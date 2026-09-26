module

public import ConnectGen.Names

public section

/-!
# Emitting service stubs

Turns a description of a proto file's services into Lean source. For a service
`ElizaService` in package `connectrpc.eliza.v1` the output declares:

* `structure ElizaService`, one field per method holding its handler. Every
  field defaults to a handler that fails with `unimplemented`, so an
  implementation only lists the methods it supports.
* `ElizaService.Spec.<method>`, each method's `Connect.MethodSpec`.
* a `Connect.ToService ElizaService` instance, so an implementation can be
  registered on a `Connect.Router`.
* `ElizaService.Client`, with one function per method.

Message types come from `protoc-gen-lean4`'s output, which the file imports.
-/

namespace ConnectGen

/-- How a method streams, as the proto file declares it. -/
inductive Streaming where
  | unary | clientStream | serverStream | bidiStream
  deriving DecidableEq, Repr, Inhabited

/-- The `idempotency_level` option. -/
inductive Idempotency where
  | unknown | noSideEffects | idempotent
  deriving DecidableEq, Repr, Inhabited

structure MethodInfo where
  /-- The method name as declared, such as `Say`. -/
  name : String
  /-- Fully-qualified request type, without a leading dot. -/
  inputType : String
  /-- Fully-qualified response type, without a leading dot. -/
  outputType : String
  streaming : Streaming
  idempotency : Idempotency := .unknown
  deprecated : Bool := false
  comment : Option String := none
  deriving Inhabited

structure ServiceInfo where
  /-- The service name as declared, such as `ElizaService`. -/
  name : String
  methods : Array MethodInfo
  comment : Option String := none
  deprecated : Bool := false
  deriving Inhabited

structure FileInfo where
  /-- Path of the proto file, such as `connectrpc/eliza/v1/eliza.proto`. -/
  protoPath : String
  package : String
  services : Array ServiceInfo
  /-- Lean modules that define the message types, to import. -/
  imports : Array String
  deriving Inhabited

structure Options where
  /-- Import for the runtime. -/
  runtimeModule : String := "Connect"
  /-- Generate server stubs. -/
  server : Bool := true
  /-- Generate clients. -/
  client : Bool := true

private def fullServiceName (file : FileInfo) (svc : ServiceInfo) : String :=
  if file.package.isEmpty then svc.name else file.package ++ "." ++ svc.name

private def docComment (indent : String) (comment : Option String) : String :=
  match comment with
  | none => ""
  | some c =>
    -- Proto comments usually start each line with one space after `//`.
    let unindent (l : String) : String := if l.startsWith " " then (l.drop 1).toString else l
    let lines := (c.trimAsciiEnd.toString.splitOn "\n").map fun l =>
      docSafe (unindent l.trimAsciiEnd.toString)
    let lines := lines.dropWhile (·.isEmpty)
    if lines.isEmpty || (lines.length == 1 && lines.head!.isEmpty) then ""
    else
      let body := "\n".intercalate (lines.map fun l => if l.isEmpty then "" else indent ++ l)
      s!"{indent}/--\n{body}\n{indent}-/\n"

/-- The Lean type of a method's handler. -/
private def handlerType (m : MethodInfo) : String :=
  let req := escapeDotted m.inputType
  let res := escapeDotted m.outputType
  match m.streaming with
  | .unary => s!"Connect.Context → {req} → Connect.RpcM {res}"
  | .serverStream => s!"Connect.Context → {req} → Connect.ResponseStream {res} → Connect.RpcM Unit"
  | .clientStream => s!"Connect.Context → Connect.RequestStream {req} → Connect.RpcM {res}"
  | .bidiStream =>
    s!"Connect.Context → Connect.RequestStream {req} → Connect.ResponseStream {res} → Connect.RpcM Unit"

private def handlerArity (m : MethodInfo) : Nat :=
  match m.streaming with
  | .unary | .clientStream => 2
  | .serverStream | .bidiStream => 3

private def streamTypeLit : Streaming → String
  | .unary => ".unary"
  | .clientStream => ".clientStream"
  | .serverStream => ".serverStream"
  | .bidiStream => ".bidiStream"

private def idempotencyLit : Idempotency → String
  | .unknown => ".unknown"
  | .noSideEffects => ".noSideEffects"
  | .idempotent => ".idempotent"

private def methodCtor : Streaming → String
  | .unary => "Connect.Method.unary"
  | .clientStream => "Connect.Method.clientStream"
  | .serverStream => "Connect.Method.serverStream"
  | .bidiStream => "Connect.Method.bidiStream"

/-- Names the generator adds next to a method's own: `serviceName` in the
    service's namespace, `connection` in its client's. A method gets one name
    for its handler field, its spec and its client function, avoiding both. -/
private def helperNames : List String := ["serviceName", "connection"]

/-- Marks a declaration deprecated, as the .proto file marks `what`. The
    protos do not say since when. -/
private def deprecatedAttr (what : String) : String :=
  s!"@[deprecated {stringLit s!"{what} is deprecated in its .proto file"} (since := \"\")]\n"

/-- Emits one service. -/
def emitService (opts : Options) (file : FileInfo) (svc : ServiceInfo) : String := Id.run do
  let fullName := fullServiceName file svc
  let svcIdent := escapeComponent svc.name
  -- Member names, in declaration order, avoiding the generated helpers.
  let mut fields : Array String := #[]
  for m in svc.methods do
    fields := fields.push (memberName m.name (fields.toList ++ helperNames))
  let mut out := ""
  -- The implementation structure.
  out := out ++ docComment "" svc.comment
  if svc.deprecated then out := out ++ deprecatedAttr fullName
  out := out ++ s!"structure {svcIdent} where\n"
  if svc.methods.isEmpty then
    out := out ++ "  /-- The service declares no methods. -/\n  «unit» : Unit := ()\n"
  for m in svc.methods, f in fields do
    out := out ++ docComment "  " m.comment
    let unimplemented := stringLit s!"{fullName}.{m.name} is not implemented"
    let args := " ".intercalate (List.replicate (handlerArity m) "_")
    out := out ++ s!"  {escapeComponent f} : {handlerType m} :=\n"
    out := out ++ s!"    fun {args} => throw (Connect.ConnectError.unimplemented {unimplemented})\n"
  out := out ++ "\n"
  out := out ++ s!"namespace {svcIdent}\n\n"
  out := out ++ s!"/-- The fully-qualified service name. -/\n"
  out := out ++ s!"def serviceName : String := {stringLit fullName}\n\n"
  -- Method specs.
  out := out ++ "namespace Spec\n\n"
  for m in svc.methods, f in fields do
    out := out ++ s!"/-- `{fullName}.{m.name}`. -/\n"
    out := out ++ s!"def {escapeComponent f} : Connect.MethodSpec where\n"
    out := out ++ s!"  service := {stringLit fullName}\n"
    out := out ++ s!"  name := {stringLit m.name}\n"
    out := out ++ s!"  streamType := {streamTypeLit m.streaming}\n"
    out := out ++ s!"  idempotency := {idempotencyLit m.idempotency}\n"
    out := out ++ s!"  requestType := {stringLit m.inputType}\n"
    out := out ++ s!"  responseType := {stringLit m.outputType}\n\n"
  out := out ++ "end Spec\n\n"
  -- Serving.
  if opts.server then
    out := out ++ s!"instance : Connect.ToService {svcIdent} where\n"
    let impl := if svc.methods.isEmpty then "_" else "impl"
    out := out ++ s!"  toService {impl} := \{\n"
    out := out ++ s!"    name := {stringLit fullName}\n"
    if svc.methods.isEmpty then
      out := out ++ "    methods := #[] }\n\n"
    else
      out := out ++ "    methods := #[\n"
      let entries := (svc.methods.zip fields).toList.map fun (m, f) =>
        s!"      {methodCtor m.streaming} Spec.{escapeComponent f} impl.{escapeComponent f}"
      out := out ++ ",\n".intercalate entries ++ "] }\n\n"
  -- The client.
  if opts.client then
    out := out ++ s!"/-- A client for `{fullName}`. -/\n"
    if svc.deprecated then out := out ++ deprecatedAttr fullName
    out := out ++ "structure Client where\n  connection : Connect.Client\n\n"
    out := out ++ "namespace Client\n\n"
    for m in svc.methods, f in fields do
      let req := escapeDotted m.inputType
      let res := escapeDotted m.outputType
      out := out ++ docComment "" m.comment
      if m.deprecated then out := out ++ deprecatedAttr s!"{fullName}.{m.name}"
      let name := escapeComponent f
      let spec := s!"Spec.{escapeComponent f}"
      out := out ++ match m.streaming with
        | .unary =>
          s!"def {name} (client : Client) (request : {req}) (options : Connect.CallOptions := \{}) :\n" ++
          s!"    Connect.RpcM {res} :=\n  client.connection.unary {spec} request options\n\n"
        | .serverStream =>
          s!"def {name} (client : Client) (request : {req}) (options : Connect.CallOptions := \{}) :\n" ++
          s!"    Connect.RpcM (Connect.ServerStreamCall {res}) :=\n" ++
          s!"  client.connection.serverStream {spec} request options\n\n"
        | .clientStream =>
          s!"def {name} (client : Client) (options : Connect.CallOptions := \{}) :\n" ++
          s!"    Connect.RpcM (Connect.ClientStreamCall {req} {res}) :=\n" ++
          s!"  client.connection.clientStream {spec} options\n\n"
        | .bidiStream =>
          s!"def {name} (client : Client) (options : Connect.CallOptions := \{}) :\n" ++
          s!"    Connect.RpcM (Connect.BidiStreamCall {req} {res}) :=\n" ++
          s!"  client.connection.bidiStream {spec} options\n\n"
    out := out ++ "end Client\n\n"
  out := out ++ s!"end {svcIdent}\n"
  return out

/-- The generated file for `file`, or `none` when it declares no services. -/
def emitFile (opts : Options) (file : FileInfo) : Option String := Id.run do
  if file.services.isEmpty then return none
  let mut out := s!"-- Generated by protoc-gen-connect-lean from {file.protoPath}. DO NOT EDIT.\n"
  out := out ++ "module\n\n"
  out := out ++ s!"public import {opts.runtimeModule}\n"
  for m in file.imports do
    out := out ++ s!"public import {m}\n"
  out := out ++ "\npublic section\n\n"
  -- Deprecations are for users; the generated code refers to what it declares.
  out := out ++ "set_option linter.deprecated false\n\n"
  let ns := escapeDotted file.package
  if !file.package.isEmpty then out := out ++ s!"namespace {ns}\n\n"
  for svc in file.services do
    out := out ++ emitService opts file svc ++ "\n"
  if !file.package.isEmpty then out := out ++ s!"end {ns}\n"
  return some out

end ConnectGen
