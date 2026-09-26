# Conformance

Programs for the [Connect conformance suite](https://github.com/connectrpc/conformance):

* `ConformanceServer.lean` — started by the runner in server mode; reads a
  `ServerCompatRequest` on stdin, starts `ConformanceService`, and reports its port.
* `ConformanceClient.lean` — started by the runner in client mode; reads
  `ClientCompatRequest`s on stdin, makes each call with `Connect.Client`, and
  reports what came back.
* `config.yaml` — the features connect-lean claims.

```bash
go install connectrpc.com/conformance/cmd/connectconformance@v1.0.5
lake build conformance-server conformance-client
connectconformance --conf conformance/config.yaml --mode server -- .lake/build/bin/conformance-server
connectconformance --conf conformance/config.yaml --mode client -- .lake/build/bin/conformance-client
```

Expected: `1980 passed, 0 failed` (server) and `2647 passed, 0 failed` (client).

`ConformanceGen/` is generated from the suite's protos (in `proto/`, exported
with `buf export buf.build/connectrpc/conformance:v1.0.4`) by `generate.sh`,
which needs `protoc` and `PROTOC_GEN_LEAN4` (see `scripts/build-protoc-gen-lean4.sh`).
