/// What the docking port has decided, rebuilt from its own decisions
/// alone, read back from the record in order (RULINGS: which conversation
/// is under which journey path "is rebuilt by reading its own decisions
/// back, not by working them out again").
library;

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show JourneyId, JourneyPathId;

import 'decision.dart';
import 'reading.dart';

/// Every decision so far, as the questions deciding the next arrival asks.
///
/// How it is used: the docking port follows `arrived`, `admitted` and
/// `declined` from the record's start. It folds each arrival through its
/// module's reading and [take]s each decision. At `caught-up` it decides,
/// in order, each arrival that has no decision. Those are only ever the
/// last few, because it records each decision before deciding the next.
/// Then it decides each new arrival as it comes. Each decision is sent
/// following [tip]. A refusal means another docking port decided first,
/// and its decision arrives to be taken like any other.
final class Decided {
  EntryHash? _tip;
  final _taken = <EntryHash>{};
  final _arrivals = <EntryHash>{};
  final _events = <(Conversation, ArrivalKey), EntryHash>{};
  final _journeyPaths = <Conversation, JourneyPathId>{};
  final _journeys = <Conversation, JourneyId>{};
  final _messages = <(Conversation, SourceMessageId), JourneyPathId>{};

  /// The last decision: what the next one follows. Null before the first.
  EntryHash? get tip => _tip;

  /// Whether [arrival] has been decided.
  bool has(EntryHash arrival) => _arrivals.contains(arrival);

  /// The arrival the event [key] in [conversation] was decided at, either
  /// way. Null when it hasn't been.
  EntryHash? decidedAt(Conversation conversation, ArrivalKey key) =>
      _events[(conversation, key)];

  /// The journey path [conversation] is under. Null when it is under none
  /// yet.
  JourneyPathId? journeyPathOf(Conversation conversation) =>
      _journeyPaths[conversation];

  /// The journey [outside] is: a conversation others sit within, such as a
  /// channel, or one that sits within nothing, such as a chat. Null before
  /// it starts.
  JourneyId? journeyOf(Conversation outside) => _journeys[outside];

  /// The journey path the message [message] in [conversation] was admitted
  /// under: where a change to it goes. Null when it was never admitted.
  JourneyPathId? journeyPathOfMessage(
    Conversation conversation,
    SourceMessageId message,
  ) => _messages[(conversation, message)];

  /// Takes in [decision], recorded at [entry]. An [Admitted] that starts a
  /// journey path or a journey names it by [entry].
  ///
  /// An entry already taken is ignored, so the docking port's own decision,
  /// taken when the record accepts it and read back later, can never move
  /// [tip] back.
  void take(EntryHash entry, Decision decision) {
    if (!_taken.add(entry)) return;
    _tip = entry;
    _arrivals.add(decision.arrival);
    switch (decision) {
      case Admitted():
        _admit(entry, decision);
      case DeclinedEvent(:final conversation, :final key, :final arrival):
        _events[(conversation, key)] = arrival;
      case Unread() || NotAdmissible():
        break;
    }
  }

  void _admit(EntryHash entry, Admitted admitted) {
    final Admitted(:conversation, :key, :message) = admitted;
    _events[(conversation, key)] = admitted.arrival;
    final outside = admitted.within ?? conversation;

    void journey(JourneyPlacement placement) {
      if (placement is StartsJourney) {
        _journeys[outside] = JourneyId.parse(entry.hex)!;
      }
    }

    final JourneyPathId? journeyPath;
    switch (admitted.placement) {
      case Under(journeyPath: final under):
        journeyPath = under;
      case StartsJourneyPath(journey: final placement):
        journey(placement);
        journeyPath = _journeyPaths[conversation] = JourneyPathId.parse(
          entry.hex,
        )!;
      case IntoJourney(journey: final placement):
        journey(placement);
        journeyPath = null;
    }
    if ((journeyPath, message) case (final path?, final message?)) {
      _messages[(conversation, message)] = path;
    }
  }
}
