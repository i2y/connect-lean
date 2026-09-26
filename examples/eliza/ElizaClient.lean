import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect

/-!
Talks to the Eliza server on localhost:8080: one unary call, a server stream,
and a conversation over a bidirectional stream.

`lake exe eliza-client [connect|grpc|grpc-web] [proto|json] [h2]`
-/

open Connect connectrpc.eliza.v1

def run (protocol : Protocol) (codec : Codec) (httpVersion : Transport.HttpVersion) : RpcM Unit := do
  let client ← Client.create { baseUrl := "http://localhost:8080", protocol, codec, httpVersion }
  let eliza : ElizaService.Client := { connection := client }

  let answer ← eliza.say { sentence := "I feel happy." }
  IO.println s!"say → {answer.sentence}"

  let intro ← eliza.introduce { name := "Lean" }
  for line in intro do
    IO.println s!"introduce → {line.sentence}"

  let chat ← eliza.converse
  for s in ["I need a proof.", "Because the types line up.", "Goodbye."] do
    chat.send { sentence := s }
  chat.closeRequest
  while true do
    let some res ← chat.receive | break
    IO.println s!"converse → {res.sentence}"
  IO.println s!"trailers: {repr (← chat.responseTrailers).entries}"

def main (args : List String) : IO UInt32 := do
  let protocol := if args.contains "grpc-web" then Protocol.grpcWeb
    else if args.contains "grpc" then .grpc else .connect
  let codec := if args.contains "json" then Codec.json else .proto
  let httpVersion := if args.contains "h2" then .http2 else Transport.HttpVersion.http1
  match ← (run protocol codec httpVersion).block with
  | .ok () => return 0
  | .error e => IO.eprintln s!"error: {e}"; return 1
