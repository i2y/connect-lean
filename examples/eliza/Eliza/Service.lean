import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect
import Eliza.Doctor

/-!
# The Eliza service

An implementation of the generated `ElizaService` structure: one handler per
method. `say` is unary, `introduce` streams from the server, and `converse`
streams both ways.
-/

open Connect connectrpc.eliza.v1

namespace Eliza

def service : ElizaService where
  say _ req := do
    return { sentence := (reply req.sentence).1 }

  introduce _ req stream := do
    let name := if req.name.isEmpty then "Anonymous User" else req.name
    for line in introduction name do
      stream.send { sentence := line }

  converse ctx requests responses := do
    for req in requests do
      let (answer, done) := reply req.sentence
      responses.send { sentence := answer }
      if done then break
    ctx.setResponseTrailer "x-session" "ended"

end Eliza
