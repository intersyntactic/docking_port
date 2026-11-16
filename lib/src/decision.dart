/// What the docking station decides about each event, each sent to the record
/// as an entry of its own (RULINGS, "The docking station admits events under
/// journey paths").
///
/// Every event is decided exactly once: [EventAdmitted] under a journey path,
/// or [EventDeclined], saying why. A decline is recorded as well as an
/// admission, so on a restart the docking station reads back what it decided
/// rather than deciding again. An event with no decision is one it had
/// not reached, never one it turned away, so a reading or a rule changed
/// since cannot admit an old event it once declined.
///
/// The decisions are one chain in the record, each following the one
/// before it. The record refuses an entry that does not follow its chain's
/// tip, so two docking stations that each believe they hold the chain cannot
/// both decide one event: the second is refused, reads the first one's
/// decision back, and goes on. "None is admitted twice" is the record's
/// guarantee, not a set one process keeps. It holds for the first decision
/// too, since that follows the start entry rather than nothing: the record
/// starts a new chain for any entry that follows nothing, so two docking
/// stations making a first decision that followed nothing would start two.
///
/// Each decision holds what it was decided on (the conversation, the
/// event's key, the message), so the docking station's state is rebuilt from
/// its decisions alone, whatever a module's reading would make of an old
/// event now.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, JourneyId, JourneyPathId;

import 'reading.dart';
import 'rules.dart';

/// The kinds of entry the docking station sends, one per event. Its user's
/// row in the record's sender table allows these three and nothing else.
abstract final class DecisionEntryKind {
  /// An [EventAdmitted]'s kind.
  static final admitted = Kind.parse('admitted')!;

  /// A [EventDeclined]'s kind.
  static final declined = Kind.parse('declined')!;

  /// An [JourneyEnded]'s kind.
  static final ended = Kind.parse('ended')!;

  /// Every kind above, as the docking station follows its own decisions.
  static final all = {admitted, declined, ended};
}

/// Where an admitted event goes. Something said, or a change, goes
/// [UnderJourneyPath] a journey path already started, or
/// [StartsJourneyPath], a new one its admission starts. A join goes
/// [IntoJourney]: it says who is in a journey, and is under none of its
/// journey paths.
sealed class AdmittedPlacement {
  const AdmittedPlacement();
}

/// Under [journeyPath], in the journey it was started in.
final class UnderJourneyPath extends AdmittedPlacement {
  const UnderJourneyPath(this.journeyPath);

  final JourneyPathId journeyPath;
}

/// Under a new journey path in [journey], which the admission starts and
/// is named by: its id is the hash of the `admitted` entry that started
/// it. A [JourneyPathId] is given by whoever starts the journey path, and
/// here that is the docking station, so the entry that started it is its one
/// name, the way a turn's id is the hash of its entry.
final class StartsJourneyPath extends AdmittedPlacement {
  const StartsJourneyPath(this.journey);

  final JourneyPlacement journey;
}

/// Into [journey]: a join, which is about who is in it.
final class IntoJourney extends AdmittedPlacement {
  const IntoJourney(this.journey);

  final JourneyPlacement journey;
}

/// Which journey: [InJourney], one already started, or [StartsJourney], a
/// new one the admission starts. A journey the docking station starts is
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

/// What the docking station decided about the event recorded at [event], and
/// [by] whom, so the record tells "the rules let it through" from "the
/// person said yes", as the airlock's does.
///
/// Every entry says who, as `"by": <who>`, where `<who>` is `rules` or
/// `person`.
sealed class AdmissionDecision {
  const AdmissionDecision(this.event, {required this.by});

  /// The event decided, by its entry's hash.
  final EntryHash event;

  /// Who decided it.
  final DecidedBy by;
}

/// [event], read as [reading], admitted by [placement].
///
/// The entry, of kind `admitted`:
///
///     {"event": <hex>, "by": <who>, "reading": <reading>,
///      ...the placement, "rules": <rules>?, "startsTurn": <bool>?}
///
/// `<reading>` is the whole reading, as [encodeReading] writes it (Nick,
/// 16 Nov: the `admitted` entry carries the reading), so whatever hands the
/// event to its journey path's apex reads the node from the decision, and
/// never reads a module's bytes. The placement is `"journeyPath": <id>` for
/// [UnderJourneyPath]; `"startsJourneyPath": true` and the journey for
/// [StartsJourneyPath]; the journey alone for [IntoJourney]. The journey is
/// `"journey": <id>` for [InJourney], or `"startsJourney": true` for
/// [StartsJourney].
///
/// [rules] are there exactly when the admission starts a journey or a
/// journey path: the rules the journey was taken in under, as the
/// [JourneyRule] gave them, copied into each path it starts. loop_launcher
/// reads a path's rules from the entry that started it, and the airlock
/// enforces them; the docking station passes them through unread.
///
/// [startsTurn] is there exactly when the reading is [MessageSaid]: whether
/// the agent answers it, as the [TurnRule] said. Something said that starts
/// no turn is still admitted under its conversation's journey path, so the
/// agent has it as context (Nick, 16 Nov: "yeah that sounds right", to
/// admitting it rather than declining it). It never starts a journey path,
/// since a path brings up an agent loop: one that starts no turn where its
/// conversation has no path yet is [SaidStartsNoTurn].
///
/// The reading's [within] is kept so which journey an outside conversation
/// is can be rebuilt from decisions alone; its [from], for rules about who
/// starts turns, such as a cap on turns bots start.
final class EventAdmitted extends AdmissionDecision {
  /// Throws an [ArgumentError] when [rules] are given for an admission
  /// that starts nothing, or missing for one that starts something; when
  /// [startsTurn] is given for anything but something said, or missing for
  /// something said; and when something said starts a journey path but no
  /// turn.
  EventAdmitted(
    super.event, {
    required super.by,
    required this.reading,
    required this.placement,
    this.rules,
    this.startsTurn,
  }) {
    if ((rules != null) != starts(placement)) {
      throw ArgumentError.value(
        rules,
        'rules',
        'given exactly when the admission starts a journey or a path',
      );
    }
    if ((startsTurn != null) != (reading is MessageSaid)) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'given exactly when the reading is something said',
      );
    }
    if (placement is StartsJourneyPath && startsTurn == false) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'something said that starts no turn starts no journey path',
      );
    }
  }

  final AdmissibleEvent reading;
  final AdmittedPlacement placement;
  final JsonObject? rules;

  /// Whether the agent answers it: for something said, and null for
  /// anything else.
  final bool? startsTurn;

  /// Whether [placement] starts a journey path or a journey.
  static bool starts(AdmittedPlacement placement) => switch (placement) {
    StartsJourneyPath() || IntoJourney(journey: StartsJourney()) => true,
    UnderJourneyPath() || IntoJourney(journey: InJourney()) => false,
  };

  ConversationId get conversation => reading.conversation;
  ConversationId? get within => reading.within;
  EventKey get key => reading.key;
  ActorId? get from => reading.from;

  /// The message it says, changes or judges; null for a join.
  SourceMessageId? get message => switch (reading) {
    MessageSaid(:final message) || MessageChanged(:final message) => message,
    ShownMessageJudged(:final to) => to,
    ConversationJoined() => null,
  };
}

/// [journey] ended, at [event]: its loops stop, its programs close and its
/// users are freed (loop_launcher), and the record takes nothing more on
/// its paths' chains (is_journal). The person's next message in it opens it
/// again, on a new path (RULINGS).
///
/// The docking station ends journeys (Nick, 16 Nov: "probably the docking
/// station should end a journey, no?", and not as a tool of the agent's).
/// What event ends one is not decided yet, so nothing decides one here; it
/// is read back like any other decision.
///
/// The entry, of kind `ended`:
///
///     {"event": <hex>, "by": <who>, "journey": <id>}
final class JourneyEnded extends AdmissionDecision {
  const JourneyEnded(super.event, {required super.by, required this.journey});

  final JourneyId journey;
}

/// [event] declined: nothing comes of it, and nothing will, whatever
/// changes later. The case says why.
///
/// The entry, of kind `declined`:
///
///     {"event": <hex>, "by": <who>, "why": <case>, ...the case's own fields}
///
/// `<case>` is `no-reading-for-source`, `reading-found-nothing`,
/// `duplicate-event`, `conversation-not-taken-in`, `said-starts-no-turn`,
/// `shown-message-judged-unplaced` or `change-to-unadmitted-message`.
sealed class EventDeclined extends AdmissionDecision {
  const EventDeclined(super.event, {required super.by});
}

/// No reading takes the event's source, or its body is not what a relay
/// records. A source whose module has no reading yet has its events
/// declined, so a reading added later starts from the events after it.
final class NoReadingForSource extends EventDeclined {
  const NoReadingForSource(super.event, {required super.by});
}

/// The module's reading found nothing to admit.
final class ReadingFoundNothing extends EventDeclined {
  const ReadingFoundNothing(super.event, {required super.by});
}

/// An event a reading named by its key, declined. A key is decided once,
/// whichever way it went, so a second event with the same key is a
/// [DuplicateEvent], even when the first was declined.
sealed class DeclinedKeyedEvent extends EventDeclined {
  const DeclinedKeyedEvent(
    super.event, {
    required super.by,
    required this.conversation,
    required this.key,
  });

  final ConversationId conversation;
  final EventKey key;
}

/// [key] in [conversation] was decided already, at the event [of]: its
/// relay recorded one thing twice, as two events with one key.
/// `"of": <hex>`.
final class DuplicateEvent extends DeclinedKeyedEvent {
  const DuplicateEvent(
    super.event, {
    required super.by,
    required super.conversation,
    required super.key,
    required this.of,
  });

  final EntryHash of;
}

/// [conversation]'s journey hasn't started, and the journey rule doesn't
/// take it in. The next event from it is asked about again.
final class ConversationNotTakenIn extends DeclinedKeyedEvent {
  const ConversationNotTakenIn(
    super.event, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// Something said that the turn rule says starts no turn, in a conversation
/// with no journey path yet. Where it has one, it is admitted, with
/// [EventAdmitted.startsTurn] false.
final class SaidStartsNoTurn extends DeclinedKeyedEvent {
  const SaidStartsNoTurn(
    super.event, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// A verdict in [conversation], which is under no journey path, so no turn
/// of the agent's there could have shown what was judged.
final class ShownMessageJudgedUnplaced extends DeclinedKeyedEvent {
  const ShownMessageJudgedUnplaced(
    super.event, {
    required super.by,
    required super.conversation,
    required super.key,
  });
}

/// A change to [message], which was never admitted, or was admitted in a
/// journey since ended, so there is no turn for it to change.
/// `"message": <source>`.
final class ChangeToUnadmittedMessage extends DeclinedKeyedEvent {
  const ChangeToUnadmittedMessage(
    super.event, {
    required super.by,
    required super.conversation,
    required super.key,
    required this.message,
  });

  final SourceMessageId message;
}
