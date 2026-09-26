import Eliza.Service

/-- Serves Eliza on port 8080 until Ctrl-C. -/
def main : IO Unit :=
  Connect.serve (Connect.Router.empty.register Eliza.service) (cfg := { port := 8080 })
