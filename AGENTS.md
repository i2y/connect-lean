# AGENTS.md

This file provides guidance to agentic coding assistants like Claude Code (claude.ai/code) when
working with code in this repository.

- [CONTRIBUTING.md](./CONTRIBUTING.md) explains how to build, test, run the conformance suite
  and regenerate code. Read [docs/architecture.md](./docs/architecture.md) before changing a
  transport or the runtime's concurrency: it records pitfalls that were expensive to find.
- Before making or proposing changes to any public API, open a GitHub issue to describe the
  proposal and gather feedback.
- Sign off every commit (`git commit -s`).
- Before finishing a change, run `lake test`. For changes to protocols, codecs or transports,
  also run both conformance suites and keep them at 0 failures.
- After changing the code generator or a `.proto` file, regenerate the checked-in code.
