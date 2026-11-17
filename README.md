# is_docking_station

The docking station is the core piece that lets the outside world into
trajectories. Something outside, such as Teams, sends bytes unasked. Its relay keeps
them in the record exactly as they came, as an *event*. The docking station
reads events from the record in order and decides, for each one, whether it
comes in and where it goes.

Each one is an entry of kind `event`. They were called arrivals until Nick
renamed them on 16 Nov ("It's an event, not an arrival"), and entries
written before then keep the kind `arrived` for good: an entry's kind is
part of the bytes its hash is taken from. So the docking station reads both.

It is the airlock's opposite. The airlock decides what leaves a trajectory
for the world. The docking station decides what comes into one. On the way back,
the docking station only says which address an answer goes to. Sending the
answer is an effect, so the airlock decides that.

The rules behind it are in intersyntactic's RULINGS ("The docking station admits
events under journey paths"). This README is how it works.

## How a module takes part: it describes, and decides nothing

A module, such as the Teams module, takes part only by giving the docking
station a *reading* (`ModuleReading`). The docking station hands the reading
every event from the module's relay, in the record's order. For each one,
the reading says what it is. The docking station never reads a module's
bytes itself, and the module never learns where anything went.

A reading is a fold. It keeps state of its own, which the docking station never
looks inside, because some events can only be read with what came before. A
quoted message's author is known from earlier events, and an edit has to be
matched to the message it edits. On every start the docking station folds again
from the record's beginning, so a reading must give the same answer for the
same events in the same order.

## What a reading names

For each event, the reading names:

- **the address** it belongs to, such as a Teams chat or a thread in a
  channel. It's written like an actor id, `teams:…`, so two modules can never
  name two addresses alike.
- **what that address sits within**, such as the channel a thread is in,
  or nothing, for a chat or for a channel itself. This is how threads are
  grouped (below), without the docking station ever reading a module's ids.
- **who it comes from**, as an `ActorId`, or no one.
- **its event key**: what "never admitted twice" compares. A relay can record
  one thing twice (Teams resends when it doesn't hear back in time), and both
  events get the same key. Two different things get different keys, even two
  edits of one message.
- **the message it concerns**, as a `SourceMessageId`, the same name the
  `UserSaid` made from it carries. An edit shares its message's *message* key,
  which is how it finds the message it edits. It has an *event* key of its
  own, so it isn't mistaken for a resend.
- **what it is**, one of the cases below.

## The cases

- **Message said** (`MessageSaid`): something said. It carries the `UserSaid`
  the trajectory appends, because only the reading holds what building one
  takes, such as a quote's author from earlier events. Something said always
  names who said it, since a `UserSaid` must have an author. So a message the
  module can't attribute is *nothing to admit*, never admitted unattributed.
- **Message changed** (`MessageChanged`): an edit, delete or restore of an
  earlier message, in the message's terms, carrying what the message became as
  conversation_shapes' `WhatChanged`: `Edited` (what it says now), `Deleted` or
  `Restored`. The trajectory's agent loop makes the node for it, a
  `UserSaidChanged`, because that node points at the turn the message became,
  and only the loop knows that turn. A module never learns turns. A change
  counts only when it comes from whoever said the message (Nick, 16 Nov), and
  whatever reads it applies that, so the docking station admits it whoever made
  it.
- **Actors joined an address** (`ActorsJoinedAddress`): people or the agent
  joined an address. Never empty: a join of no one is nothing to admit.
- **Shown message judged** (`ShownMessageJudged`): a person's verdict on
  something the agent showed them, such as Approve, Not yet or a proposed
  correction on a card. It is named for what it says, not for the button: a
  Slack button would be the same thing. It names the message judged, and the
  verdict as is_annotation_shapes' `VerdictOnShownMessage`: `ApprovedVerdict`,
  `HeldOffVerdict` or `ProposedCorrectionVerdict`. As with a change, the
  trajectory's agent loop builds the annotation (a `NodeApproval`, a `NodeSeenMark`, a
  `NodeCorrection`) once it knows which turn the message showed. A verdict
  always names who gave it, since a verdict from no one approves nothing.
- **Nothing to admit** (`NothingToAdmit`): a typing indicator, a reaction the
  module doesn't carry, anything it can't read.

Whether something said starts a turn is not the reading's call. The docking
station decides that, under the trajectory's rules.

## Missions and trajectories

An address in an external system that holds threads, such as a Teams
channel, is a *mission*, and each of its threads is one of that mission's
*trajectories*. An address with no threads, such as a chat, is a mission with
one trajectory. It's the shape the core already has: a mission holds the
people working in it and its trajectories, and a trajectory is one agent's
line of turns. (Nick named them journeys and journey paths on 15 Nov and
renamed them missions and trajectories on 17 Nov.)

What the docking station writes for each event, and the words in it:

| Entry kind | When |
|---|---|
| `event-admitted-to-mission` | The event comes in, on a trajectory or into a mission |
| `event-not-admitted-to-mission` | It stays out; `why` says which case |
| `mission-ended` | A mission is over, and the journal closes its chains |

The start entry, `docking-station-set-up`, is written once at setup by
infra's `record-setup` user, never by the docking station. A reading carries
`addressInExternalSystem` and, when it sits inside another,
`containingAddress`.

A mission starts with the first thread admitted under it. It needs no join of
its own: an event from an address already shows the agent is in it. A
join is kept in the mission of the address it comes from, even when it
means more, as a Teams join does when the agent is added to a whole team.
How Teams sends that is Teams' business, so it's in teams_module's README.

## What a module never does

A module never composes trajectories, never keeps which address is
under which trajectory, and never runs an agent loop. Working with many
trajectories is the core's job, so every module that brings addresses in
uses the same one.

## Where it stands

- **Built:** the reading contract: `RelayedEvent`, `ModuleReading`,
  `EventReading` and its cases, `AddressInExternalSystem`, `EventKey`. Admission,
  meaning the decision recorded for each event, the rules passed in, and
  rebuilding from the record
  (https://github.com/intersyntactic/docking_station/pull/2,
  https://github.com/intersyntactic/docking_station/pull/3); who made each
  decision (https://github.com/intersyntactic/docking_station/pull/5); reading
  the record and sending each decision
  (https://github.com/intersyntactic/docking_station/pull/6), now through
  `is_journal_client`; the start entry
  (https://github.com/intersyntactic/docking_station/pull/15); and
  `path_start.dart`, the airlock's narrow reader
  (https://github.com/intersyntactic/docking_station/pull/14).
- **Not yet:** the service that runs it on a machine, with a real
  `JournalReader` and `JournalWriter`.
- **Coming:** handing admitted events to a trajectory's agent loop.
