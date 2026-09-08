# Memory without the system

*More memory than message: running a team of agents on enveloped letters.*

A multi-agent setup built around conversation leaves its decisions somewhere
in the scroll: agents talk, the transcript rolls on. Ours is built around
enveloped letters.

## The shape of it

The post is one of the oldest systems still running, proven over centuries —
and its underrated half was never the letter. It was the envelope: sender,
addressee, date, the promise of a way back. Without those, a letter is just
paper and ink that didn't arrive.

Each agent has a letterbox — a directory of durable Markdown letters. Work
arrives as a letter; it is acknowledged, updated, and answered; and when it
is done, the exchange is still there, addressable by id,
exactly as it was written. A doorbell tells a waiting agent that a letter has
landed. The bell is how anyone learns a letter exists; the letter is what
survives.

Each letter carries its own envelope — who it is from, who it is for, its id,
and when it was sent — so it can be found, cited and answered without
hunting through a transcript. We call that an **enveloped letter**, and the envelope is the heart of
the whole idea: it is what turns a message into a record. An archive of them
is addressable rather than a heap — "check letter such-and-such" works because
every letter knows its own name — and that archive is the team's **enveloped
memory**: every remembered thing carrying its own provenance on its face.

The team on such a stack is deliberately mixed — a dynamic, lead-driven
multi-agent team, and the members can be almost any CLI agent: Claude Code,
Codex, Grok, Kimi, Pi, Hermes, or whatever comes next. Different vendors'
models, different runtimes, different strengths: one thinks slowly and deeply,
one builds, one reads adversarially, one holds the longest context. The mail
system is what lets them be *different* and still be a team — because what
travels between them is explicit, written handoffs that each seat answers in
its own way.

## What the record does for a team

**Conclusions can be checked, not just believed.** When one seat claims
something — a review verdict, a measurement, a decision someone made — any
other seat can open the letter it points to and read what was actually said.
Disagreements get settled against the record instead of against whoever
remembers loudest. That is the practice worth building: claims that point at
their sources, and reviewers who open them.

**It is the memory, without being a memory system.** This is the part that
surprises people. There is no database, no embeddings, no recall engine — and
yet the team demonstrably has a memory, because the letters *are* it. Ask what
was decided last month and the answer is not generated, it is *there*, in the
exchange where it happened. The deliberate absence is the machinery that would
answer on the record's behalf: the retained original text is there to return
to, so no summary has to be trusted in its place. Memory as record, not
memory as service.

**The record outlasts the session.** Sessions end, models get upgraded,
machines restart. The letters don't move. A seat that comes back after a week
reads its inbox from primary sources rather than from a briefing, and a
recorded exchange can be revisited months later exactly as it was written:
what was asked, what was answered, and when.

**Handovers are real.** Because a task arrives as a letter with an id, it can
be acknowledged, declined, or delivered against — explicitly. Nothing is
"sort of assigned". The lifecycle is small and honest: tasks are acknowledged,
updated, and closed with a result or a decline — and a letter nobody answered
stays visibly open rather than quietly forgotten.

**Decisions stay decided** — and this one is practice layered on the record,
not a property of the letterbox. House rules and standing decisions live where
the work happens — in the contribution docs editors actually read, with the
mechanically checkable ones enforced by small gates at commit time. The
letterbox doesn't enforce house rules; it makes the habit cheap enough to keep,
and the habit does the enforcing.

## What the operator gets

The Bridge brings the operator's messages into the same durable record and
carries replies back to their source chat — from a phone, if that is where
the operator lives; nothing requires it. A decision sent through it lands as
a letter too, which means the team can point at it later, and does. The human is not a bottleneck reading transcripts; they are the
addressee of short, precise reports and the source of decisions with ids.

## What you bring

The software carries the letters: durably, addressably, honestly — a ring never
claims a letter was read, and local mailbox delivery is backed by a file, not
a hope. What a team layers on top is its own: which seats review which work,
what gets checked twice, which decisions get written down. The tools were
built to make those habits cheap and checkable. The habits are the part that
compounds.

One useful way to build on this: the letterbox first, then the
bridge bringing the human's phone into the same letter discipline — and on
top of both, a review habit the record makes possible: being wrong in a
checkable way, which is the only way a team of very confident writers
actually improves.

---

*Everything above is a design property of the public tools or a practice any
team can adopt with them. Products:
[agent-letterbox](https://github.com/SimonMallas/agent-letterbox-cmux)
([cmux](https://github.com/SimonMallas/agent-letterbox-cmux),
[tmux](https://github.com/SimonMallas/agent-letterbox-tmux),
[Herdr](https://github.com/SimonMallas/agent-letterbox-herdr),
[Zellij](https://github.com/SimonMallas/agent-letterbox-zellij) editions) and
[agent-letter-bridge](https://github.com/SimonMallas/agent-letter-bridge).*
