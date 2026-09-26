import Tests.Harness
import Tests.Core
import Tests.Gzip
import Tests.Integration
import Tests.Http2
import Tests.Edge
import Tests.Robustness

/-- `tests [filter]`: runs the tests whose names contain `filter`. -/
def main (args : List String) : IO UInt32 :=
  Tests.runAll (filter := args.headD "") [
    ("codes", Tests.Core.codeTests),
    ("base64", Tests.Core.base64Tests),
    ("headers", Tests.Core.headerTests),
    ("envelopes", Tests.Core.envelopeTests),
    ("errors", Tests.Core.errorTests),
    ("protocols", Tests.Core.protocolTests),
    ("gzip", Tests.Gzip.tests),
    ("hpack", Tests.Http2.tests),
    ("http2 frames", Tests.Http2.frameTests),
    ("integration", Tests.Integration.tests),
    ("robustness", Tests.Robustness.tests),
    ("generated code", Tests.Edge.tests)
  ]
