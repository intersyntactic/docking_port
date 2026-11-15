# is_docking_port

The docking port is the core piece that lets the outside world into journey
paths. Something outside, such as Teams, sends bytes unasked. Its relay keeps
them in the record exactly as they came, as an *arrival*. The docking port
reads arrivals from the record in order and decides, for each one, whether it
comes in and where it goes.

It is the airlock's opposite. The airlock decides what leaves a journey path
for the world. The docking port decides what comes into one. On the way back,
the docking port only says which conversation an answer goes to. Sending the
answer is an effect, so the airlock decides that.

The rules behind it are in intersyntactic's RULINGS ("The docking port admits
arrivals under journey paths"). This README is how it works.

## How a module takes part: it describes, and decides nothing

A module, such as the Teams module, takes part only by giving the docking port
a *reading* (`ModuleReading`). The docking port hands the reading every
arrival from the module's relay, in the record's order. For each one, the
reading says what it is. The docking port never reads a module's bytes
itself, and the module never learns where anything went.

A reading is a fold. It keeps state of its own, which the docking port never
looks inside, because some arrivals can only be read with what came before.
A quoted message's author is known from earlier arrivals, and an edit has to
be matched to the message it edits. On every start the docking port folds
again from the record's beginning, so a reading must give the same answer
for the same arrivals in the same order.

## What a reading names

For each arrival, the reading names:

- **the conversation** it belongs to, such as a Teams chat or a thread in a
  channel. It's written like an actor id, `teams:…`, so two modules can never
  name two conversations alike.
- **what that conversation sits within**, such as the channel a thread is in,
  or nothing, for a chat or for a channel itself. This is how threads are
  grouped (below), without the docking port ever reading a module's ids.
- **who it comes from**, as an `ActorId`, or no one.
- **its arrival key**: what "never admitted twice" compares. A relay can
  record the same event twice (Teams resends when it doesn't hear back in
  time), and both copies get the same arrival key. Two different events get
  different keys, even two edits of one message.
- **the message it concerns**, as a `SourceMessageId`, the same name the
  `UserSaid` made from it carries. An edit shares its message's *message* key,
  which is how it finds the message it edits. It has an *arrival* key of its
  own, so it isn't mistaken for a resend.
- **what it is**, one of the cases below.

## The cases

- **Said** (`Said`): something said. It carries the `UserSaid` the journey
  path appends, because only the reading holds what building one takes, such
  as a quote's author from earlier arrivals. Something said always names who
  said it, since a `UserSaid` must have an author. So a message the module
  can't attribute is *nothing to admit*, never admitted unattributed.
- **Changed** (`Changed`): an edit or delete of an earlier message, in the
  message's terms. The journey path's agent loop makes the node for it,
  because that node points at the turn the message became, and only the loop
  knows that turn. A module never learns turns. *Coming:* what the message
  became (new text, deleted, restored), a shape conversation_shapes will
  define.
- **Joined** (`Joined`): people or the agent joined a conversation. Never
  empty: a join of no one is nothing to admit.
- **Responded** (`Responded`): a person's response to something the agent
  showed them, such as Approve, Not yet or a proposed correction on a card.
  It is named for what it says, not for the button: a Slack button would be
  the same thing. It names the message responded to, and the response as
  is_annotation_shapes' `Response`: `Approved`, `HeldOff` or `Proposed`. As
  with a change, the journey path's agent loop builds the annotation (an
  `Approval`, a `Seen`, a `Correction`) once it knows which turn the message
  showed. A response always names who responded, since a response from no
  one approves nothing.
- **Nothing to admit** (`NothingToAdmit`): a typing indicator, a reaction the
  module doesn't carry, anything it can't read.

Whether something said starts a turn is not the reading's call. The docking
port decides that, under the journey path's rules.

## Journeys and journey paths

An outside conversation that holds threads, such as a Teams channel, is a
*journey*, and each of its threads is one of that journey's *journey paths*.
A conversation with no threads, such as a chat, is a journey with one journey
path. It's the shape the core already has: a journey holds the people working
in it and its journey paths, and a journey path is one agent's thread.

A journey starts with the first thread admitted under it. It needs no join of
its own: an arrival from a conversation already shows the agent is in it. A
join is kept in the journey of the conversation it arrives in, even when it
means more. In Teams, adding the agent to a team arrives once, in the team's
General channel.

## What a module never does

A module never composes journey paths, never keeps which conversation is
under which journey path, and never runs an agent loop. Working with many
journey paths is the core's job, so every module that brings conversations in
uses the same one.

## Where it stands

- **Built:** the reading contract: `Arrival`, `ModuleReading`, `Reading` and
  its cases, `Conversation`, `ArrivalKey`.
- **Proposed, not agreed:** admission, meaning the decision recorded for each
  arrival, the rules passed in, and rebuilding from the record
  (https://github.com/intersyntactic/docking_port/pull/2).
- **Coming:** what a `Changed` message became; handing admitted arrivals to
  a journey path's agent loop.
