import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect

/-!
A rough throughput check: a server and clients in one process, `workers`
concurrent callers making unary calls for a few seconds.

`lake exe bench [connect|grpc|grpc-web] [h2] [workers] [seconds]`
-/

open Connect connectrpc.eliza.v1

def echo : ElizaService where
  say _ req := return { sentence := req.sentence }

partial def worker (client : ElizaService.Client) (deadline : Nat) (count : IO.Ref Nat) : RpcM Unit := do
  if (← IO.monoMsNow) ≥ deadline then return
  let _ ← client.say { sentence := "hello" }
  count.modify (· + 1)
  worker client deadline count

def main (args : List String) : IO Unit := do
  let protocol := if args.contains "grpc-web" then Protocol.grpcWeb
    else if args.contains "grpc" then .grpc else .connect
  let httpVersion := if args.contains "h2" then Transport.HttpVersion.http2 else .http1
  let nums := args.filterMap String.toNat?
  let workers := nums[0]?.getD 16
  let seconds := nums[1]?.getD 5
  let running ← Server.start (Router.empty.register echo) {} { port := 0 }
  let conn ← Client.create { baseUrl := s!"http://127.0.0.1:{running.port}", protocol, httpVersion }
  let client : ElizaService.Client := { connection := conn }
  let count ← IO.mkRef 0
  let start ← IO.monoMsNow
  let deadline := start + seconds * 1000
  let calls := (Array.range workers).map fun _ => RpcM.run (worker client deadline count)
  let results ← Std.Async.Async.block (Std.Async.EAsync.concurrentlyAll calls)
  let elapsed := (← IO.monoMsNow) - start
  let n ← count.get
  let failures := results.filter (·.toBool == false) |>.size
  IO.println s!"{protocol} over {repr httpVersion}, {workers} workers: {n} calls in {elapsed} ms = {n * 1000 / elapsed} calls/s ({failures} workers failed)"
  running.shutdown
