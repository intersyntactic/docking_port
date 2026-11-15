/// What the docking port decides about each arrival, each sent to the record
/// as an entry of its own (RULINGS, "The docking port admits arrivals under
/// journey paths").
///
/// Every arrival is decided exactly once: [Admitted] under a journey path,
/// or [Declined], saying why. A decline is recorded as well as an
/// admission, so on a restart the docking port reads back what it decided
/// rather than deciding again. An arrival with no decision is one it had
/// not reached, never one it turned away, so a reading or a rule changed
/// since cannot admit an old arrival it once declined.
///
/// The decisions are one chain in the record, each following the one
/// before it. The record refuses an entry that does not follow its chain's
/// tip, so two docking ports that each believe they hold the chain cannot
/// both decide one arrival: the second is refused, reads the first one's
/// decision back, and goes on. "None is admitted twice" is the record's
/// guarantee, not a set one process keeps.
///
/// Each decision holds what it was decided on (the conversation, the
/// event's key, the message), so the docking port's state is rebuilt from
/// its decisions alone, whatever a module's reading would make of an old
/// arrival now.
library;

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, JourneyId, JourneyPathId;

import 'reading.dart';

/// The kinds of entry the docking port sends, one per arrival. Its user's
/// row in the record's sender table allows these two and nothing else.
abstract final class DecisionKind {
  /// An [Admitted]'s kind.
  static final admitted = Kind.parse('admitted')!;

  /// A [Declined]'s kind.
  static final declined = Kind.parse('declined')!;
}

/// Where an admitted arrival goes. Something said, or a change, goes
/// [Under] a journey path already started, or [StartsJourneyPath], a new
/// one its admission starts. A join goes [IntoJourney]: it says who is in
/// a journey, and is under none of its journey paths.
sealed class Placement {
  const Placement();
}

/// Under [journeyPath], in the journey it was started in.
final class Under extends Placement {
  const Under(this.journeyPath);

  final JourneyPathId journeyPath;
}

/// Under a new journey path in [journey], which the admission starts and
/// is named by: its id is the hash of the `admitted` entry that started
/// it. A [JourneyPathId] is given by whoever starts the journey path, and
/// here that is the docking port, so the entry that started it is its one
/// name, the way a turn's id is the hash of its entry.
final class StartsJourneyPath extends Placement {
  const StartsJourneyPath(this.journey);

  final JourneyPlacement journey;
}

/// Into [journey]: a join, which is about who is in it.
final class IntoJourney extends Placement {
  const IntoJourney(this.journey);

  final JourneyPlacement journey;
}

/// Which journey: [InJourney], one already started, or [StartsJourney], a
/// new one the admission starts. A journey the docking port starts is
/// named like a journey path it starts, by the `admitted` entry's hash, as
/// a [JourneyId]. One entry can start both, as a chat's first message
/// does, and then both have its hash, as two kinds of name.
sealed class JourneyPlacement {
  const JourneyPlacement();
}

/// In [journey], already started.
final class InJourney extends JourneyPlacement {
  const InJourney(this.journey);

  final JourneyId journey;
}

/// In a new journey, which the admission starts.
final class StartsJourney extends JourneyPlacement {
  const StartsJourney();
}

/// What the docking port decided about the `arrived` entry [arrival], and
/// [by] whom, so the record tells "the rules let it through" from "the
/// person said yes", as the airlock's does.
///
/// Every entry says who, as `"by": <who>`, where `<who>` is `rules` or
/// `person`.
sealed class Decision {
  const Decision(this.arrival, {required this.by});

  /// The `arrived` entry decided.
  final EntryHash arrival;

  /// Who decided it.
  final DecidedBy by;
}

/// [arrival] admitted by [placement]: the event [key] in [conversation],
/// which sits within [within], from [from], about [message].
///
/// The entry, of kind `admitted`:
///
///     {"arrival": <hex>, "by": <who>, "conversation": <id>, "within": <id>?,
///      "key": <key>, "from": <actor id>?, "message": <source>?,
///      ...the placement}
///
/// The placement is `"journeyPath": <id>` for [Under];
/// `"startsJourneyPath": true` and the journey for [StartsJourneyPath]; the
/// journey alone for [IntoJourney]. The journey is `"journey": <id>` for
/// [InJourney], or `"startsJourney": true` for [StartsJourney].
///
/// [within] is kept so which journey an outside conversation is can be
/// rebuilt from decisions alone; [from], for rules about who starts turns,
/// such as a cap on turns bots start.
final class Admitted extends Decision {
  const Admitted(
    super.arrival, {
    required super.by,
    required this.conversation,
    required this.within,
    required this.key,
    required this.from,
    required this.message,
    required this.placement,
  });

  final Conversation conversation;
  final Conversation? within;
  final ArrivalKey key;
  final ActorId? from;

  /// The message it says, changes or responds to; null for a join.
  final SourceMessageId? message;

  final Placement placement;
}

/// [arrival] declined: nothing comes of it, and nothing will, whatever
/// changes later. The case says why.
///
/// The entry, of kind `declined`:
///
///     {"arrival": <hex>, "by": <who>, "why": <case>, ...the case's own fields}
///
/// `<case>` is `unread`, `not-admissible`, `duplicate`, `not-taken-in`,
/// `not-a-turn`, `responds-unplaced` or `changes-unadmitted`.
sealed class Declined extends Decision {
  const Declined(super.arrival, {required super.by});
}

/// No reading takes the arrival's source, or its body is not what a relay
/// records. A source whose module has no reading yet has its arrivals
/// declined, so a reading added later starts from what arrives after it.
final class Unread extends Declined {
  const Unread(super.arrival, {required super.by});
}

/// The module's reading found nothing to admit.
final class NotAdmissible extends Declined {
  const NotAdmissible(super.arrival, {required super.by});
}

/// An event a reading named, declined. It is decided once whichever way
/// it went, so a second delivery of it is a [Duplicate], even of an event
/// first declined.
sealed class DeclinedEvent extends Declined {
  const DeclinedEvent(
    super.arrival, {
    required super.by,
    required this.conversation,
    required this.key,
  });

  final Conversation conversation;
  final ArrivalKey key;
}

/// The event [key] in [conversation] was decided already, at the arrival
/// [of]: its relay recorded it twice. `"of": <hex>`.
final class Duplicate extends DeclinedEvent {
  const Duplicate(
    super.arrival, {
    required super.by,
    required super.conversation,
    required super.key,
    required this.of,
  });

  final EntryHash of;
}

/// [conversation]'s journey hasn't started, and the journey rule doesn't
/// take it in. The next event from it is asked about again.
final class NotTakenIn extends DeclinedEvent {
  const NotTakenIn(
    super.arrival, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// Something said that the turn rule says starts no turn.
final class NotATurn extends DeclinedEvent {
  const NotATurn(
    super.arrival, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// A response in [conversation], which is under no journey path, so no turn
/// of the agent's there could have shown what was responded to.
final class RespondsUnplaced extends DeclinedEvent {
  const RespondsUnplaced(
    super.arrival, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// A change to [message], which was never admitted, so there is no turn
/// for it to change. `"message": <source>`.
final class ChangesUnadmitted extends DeclinedEvent {
  const ChangesUnadmitted(
    super.arrival, {
    required super.by,
    required super.conversation,
    required super.key,
    required this.message,
  });

  final SourceMessageId message;
}
