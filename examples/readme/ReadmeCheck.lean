import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect

/-! The code in README.md, compiled so that it stays true. -/

namespace ReadmeCheck

open Connect connectrpc.eliza.v1

def eliza : ElizaService where
  -- unary: one request, one response
  say ctx req := do
    ctx.setResponseHeader "x-served-by" "lean"
    if req.sentence.isEmpty then
      throw (.invalidArgument "say something")
    return { sentence := s!"You said: {req.sentence}" }

  -- server streaming: send as many responses as you like
  introduce _ req stream := do
    for line in ["Hello, " ++ req.name, "I'm Eliza."] do
      stream.send { sentence := line }

  -- bidirectional: read requests as they come, answer each
  converse _ requests responses := do
    for req in requests do
      responses.send { sentence := s!"Why do you say {req.sentence}?" }

def serveMain : IO Unit :=
  Connect.serve (Router.empty.register eliza) (cfg := { port := 8080 })

def timing : MetadataInterceptor Nat where
  onStart _ := IO.monoMsNow
  onEnd started ctx err? := do
    let ms := (← IO.monoMsNow) - started
    IO.eprintln s!"{ctx.spec.procedure}: {ms} ms, {(err?.map toString).getD "ok"}"

def auth : Interceptor := .before fun ctx => do
  unless ctx.requestHeaders.get? "authorization" == some "Bearer secret" do
    throw (.unauthenticated "missing token")

-- Logs every unary request, on either side.
def logRequests : MessageInterceptor where
  unary next ctx req := do
    IO.eprintln s!"{ctx.spec.procedure} {← Message.toJsonString req}"
    next ctx req

-- On a client: sends a token with every unary call.
def withToken : MessageInterceptor where
  unary next ctx req := do
    next { ctx with requestHeaders := ctx.requestHeaders.set "authorization" "Bearer secret" } req

def interceptedClient : IO Connect.Client := do
  let connection ← Connect.Client.create {
    baseUrl := "http://localhost:8080", interceptors := #[withToken, timing] }
  return connection

def serveWithOptions (router : Router) : IO Unit :=
  Connect.serve router {
    readMaxBytes := 1024 * 1024                -- largest request message
    compressions := #[Compression.gzip]        -- besides identity
    interceptors := #[auth, timing, logRequests] -- first one outermost
  }

def clientMain : IO Unit := do
  let connection ← Connect.Client.create { baseUrl := "http://localhost:8080" }
  let eliza : ElizaService.Client := { connection }
  let reply ← (eliza.say { sentence := "I feel happy" }).toIO
  IO.println reply.sentence

def streams (eliza : ElizaService.Client) : RpcM Unit := do
  -- server streaming: iterate over the responses
  for res in (← eliza.introduce { name := "Lean" }) do
    IO.println res.sentence

  -- bidirectional: send, close, receive
  let chat ← eliza.converse
  chat.send { sentence := "Hi" }
  chat.closeRequest
  while true do
    let some res ← chat.receive | break
    IO.println res.sentence

def grpcClient : IO Connect.Client := do
  let connection ← Connect.Client.create {
    baseUrl := "http://localhost:8080", protocol := .grpc }
  return connection

def withMetadata (client : ElizaService.Client) (req : SayRequest) : RpcM (UnaryResponse SayResponse) :=
  client.connection.unaryWithMetadata ElizaService.Spec.say req

end ReadmeCheck
