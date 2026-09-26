/-!
# The DOCTOR script, abridged

A small, deterministic ELIZA: it matches a few sentence openings, reflects the
rest back ("my job" becomes "your job"), and otherwise falls back on a stock
reply. Ported loosely from connectrpc/examples-go.
-/

namespace Eliza

/-- Swaps first and second person, so a fragment can be echoed back. -/
def reflect (fragment : String) : String :=
  let swap : String → String
    | "i" => "you" | "me" => "you" | "my" => "your" | "am" => "are" | "mine" => "yours"
    | "you" => "I" | "your" => "my" | "yours" => "mine" | "are" => "am" | w => w
  " ".intercalate ((fragment.splitOn " ").filter (!·.isEmpty) |>.map swap)

/-- Sentence openings and the replies they prompt; `{}` is the reflected rest. -/
def patterns : List (String × List String) := [
  ("i need ", ["Why do you need {}?", "Would it really help you to get {}?"]),
  ("i feel ", ["Tell me more about feeling {}.", "Do you often feel {}?"]),
  ("i am ", ["How long have you been {}?", "Why do you tell me you're {}?"]),
  ("i think ", ["Do you doubt {}?", "Do you really think so?"]),
  ("because ", ["Is that the real reason?", "What other reasons come to mind?"]),
  ("why don't you ", ["Do you really think I don't {}?", "Perhaps eventually I will {}."]),
  ("my ", ["I see, your {}.", "Why do you say that your {}?"]),
  ("you ", ["We should be discussing you, not me.", "Why do you say that about me?"])]

def defaults : List String := [
  "Please tell me more.", "Let's change focus a bit... Tell me about your family.",
  "Can you elaborate on that?", "I see.", "Very interesting.", "How does that make you feel?"]

private def pick (choices : List String) (seed : String) : String :=
  choices[(hash seed).toNat % choices.length]!

private def normalize (s : String) : String :=
  let s := s.trimAscii.toString.toLower
  String.ofList (s.toList.reverse.dropWhile (fun c => ".!?'\"".contains c) |>.reverse)

/-- Eliza's answer, and whether the conversation is over. -/
def reply (sentence : String) : String × Bool :=
  let s := normalize sentence
  if ["bye", "goodbye", "quit", "exit"].contains s then
    ("Goodbye. It was nice talking to you.", true)
  else
    match patterns.find? (fun (p, _) => s.startsWith p) with
    | some (p, replies) =>
      let reply := pick replies s
      (reply.replace "{}" (reflect (s.drop p.length).toString), false)
    | none => (pick defaults s, false)

/-- How Eliza introduces herself to `name`. -/
def introduction (name : String) : List String := [
  s!"Hi {name}. I'm Eliza.",
  "Before we begin, let me tell you something about myself.",
  "I was created by Joseph Weizenbaum at MIT in the 1960s.",
  "How are you feeling today?"]

end Eliza
