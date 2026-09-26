import Connect
import EdgeGen.edge.v1.edge_connect
import EdgeGen.nopkg_connect
import Tests.Harness

/-! Generated code for awkward names compiles, and works end to end. -/

namespace Tests.Edge
open Connect edge.v1

def impl : EdgeService where
  client _ req := return { text := s!"client {req.text}" }
  connection_ _ req := return { text := s!"connection {req.text}" }
  mk_ _ req := return { text := s!"mk {req.text}" }
  «end» _ req := return { text := s!"end {req.text}" }
  «where» _ reqs out := do
    for r in reqs do out.send { text := s!"where {r.text}" }
  get_thing ctx req := return { text := s!"{ctx.httpMethod} {req.text}" }

def greeter : Greeter where
  greet _ req := return { name := s!"hello {req.name}" }

/-! What the .proto file deprecates warns where it is used, and only there. -/

/--
warning: `edge.v1.OldService` has been deprecated: edge.v1.OldService is deprecated in its .proto file
-/
#guard_msgs in
example : OldService := {}

/--
warning: `edge.v1.EdgeService.Client.deprecated` has been deprecated: edge.v1.EdgeService.Deprecated is deprecated in its .proto file
-/
#guard_msgs in
example (c : EdgeService.Client) := c.deprecated {}

def tests : List Test := [
  ("awkward method names round-trip", do
    let running ← Server.start ((Router.empty.register impl).register greeter) {} { port := 0 }
    try
      let conn ← Client.create { baseUrl := s!"http://127.0.0.1:{running.port}", useHttpGet := true }
      let c : EdgeService.Client := { connection := conn }
      expectEq (← (c.client { text := "a" }).toIO).text "client a"
      expectEq (← (c.mk_ { text := "b" }).toIO).text "mk b"
      expectEq (← (c.connection_ { text := "b" }).toIO).text "connection b"
      expectEq (← (c.«end» { text := "c" }).toIO).text "end c"
      expectEq (← (c.get_thing { text := "d" }).toIO).text "GET d"
      let e ← (c.serviceName_ { text := "x" }).block
      expect (match e with | Except.error err => err.code == .unimplemented | _ => false)
        "default handler"
      let stream ← (c.«where» {}).toIO
      let answers ← (do
        stream.send { text := "w" }
        stream.closeRequest
        let mut out := #[]
        repeat
          let some r ← stream.receive | break
          out := out.push r.text
        return out : RpcM (Array String)).toIO
      expectEq answers #["where w"]
      let g : Greeter.Client := { connection := conn }
      expectEq (← (g.greet { name := "root" }).toIO).name "hello root"
      expectEq EdgeService.serviceName "edge.v1.EdgeService"
      expectEq EmptyService.serviceName "edge.v1.EmptyService"
    finally
      running.shutdown)
]

end Tests.Edge
