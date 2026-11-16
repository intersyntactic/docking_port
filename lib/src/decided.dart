/// What the docking station has decided, rebuilt from its own decisions
/// alone, read back from the record in order (RULINGS: which conversation
/// is under which journey path "is rebuilt by reading its own decisions
/// back, not by working them out again").
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show JourneyId, JourneyPathId;

import 'decision.dart';
import 'reading.dart';

/// Every decision so far, as the questions deciding the next event asks.
///
/// How it is used: the docking station subscribes to the record's events and
/// its own `admitted` and `declined` entries from the record's start. It
/// folds each event through its module's reading and [take]s each decision.
/// At `caught-up` it decides, in order, each event that has no decision.
/// Those are only ever the last few, because it records each decision
/// before deciding the next. Then it decides each new event as it comes.
/// Each decision is sent naming [tip] as previous. A `not-tip` refusal means
/// another docking station decided first, and its decision comes on the
/// record to be taken like any other.
final class DecidedSoFar {
  EntryHash? _tip;
  final _taken = <EntryHash>{};
  final _decidedEvents = <EntryHash>{};
  final _events = <(ConversationId, EventKey), EntryHash>{};
  final _journeyPaths = <ConversationId, JourneyPathId>{};
  final _pathJourneys = <JourneyPathId, JourneyId>{};
  final _journeys = <ConversationId, JourneyId>{};
  final _rules = <JourneyId, JsonObject>{};
  final _messages = <(ConversationId, SourceMessageId), JourneyPathId>{};

  /// The last decision: what the next one names as previous. Null before the
  /// first.
  EntryHash? get tip => _tip;

  /// Whether [event] has been decided.
  bool has(EntryHash event) => _decidedEvents.contains(event);

  /// The event that [key] in [conversation] was decided at, whichever way
  /// it went. Null when no event with that key has been decided.
  EntryHash? decidedAt(ConversationId conversation, EventKey key) =>
      _events[(conversation, key)];

  /// The journey path [conversation] is under. Null when it is under none
  /// yet.
  JourneyPathId? journeyPathOf(ConversationId conversation) =>
      _journeyPaths[conversation];

  /// The journey [outside] is: a conversation others sit within, such as a
  /// channel, or one that sits within nothing, such as a chat. Null before
  /// it starts.
  JourneyId? journeyOf(ConversationId outside) => _journeys[outside];

  /// The rules [journey] was taken in under. Only for a journey that
  /// [journeyOf] has given, since every entry that starts one records them.
  JsonObject rulesOf(JourneyId journey) => _rules[journey]!;

  /// The journey path the message [message] in [conversation] was admitted
  /// under: where a change to it goes. Null when it was never admitted.
  JourneyPathId? journeyPathOfMessage(
    ConversationId conversation,
    SourceMessageId message,
  ) => _messages[(conversation, message)];

  /// Takes in [decision], recorded at [entry]. An [EventAdmitted] that starts a
  /// journey path or a journey names it by [entry].
  ///
  /// An entry already taken is ignored, so the docking station's own decision,
  /// taken when the record accepts it and read back later, can never move
  /// [tip] back.
  void take(EntryHash entry, AdmissionDecision decision) {
    if (!_taken.add(entry)) return;
    _tip = entry;
    _decidedEvents.add(decision.event);
    switch (decision) {
      case EventAdmitted():
        _admit(entry, decision);
      // The first event with a key keeps it, so every duplicate after names
      // that one, never the copy before it.
      case DeclinedKeyedEvent(:final conversation, :final key, :final event):
        _events.putIfAbsent((conversation, key), () => event);
      case JourneyEnded(:final journey):
        _end(journey);
      case NoReadingForSource() || ReadingFoundNothing():
        break;
    }
  }

  /// Forgets [journey]'s paths, whose chains the record now closes, and
  /// the messages admitted under them. A conversation in it then starts a
  /// new path, in the same journey, and a change to a message admitted
  /// before the end is a change to one never admitted.
  void _end(JourneyId journey) {
    final ended = {
      for (final MapEntry(key: path, value: of) in _pathJourneys.entries)
        if (of == journey) path,
    };
    _journeyPaths.removeWhere((_, path) => ended.contains(path));
    _messages.removeWhere((_, path) => ended.contains(path));
    _pathJourneys.removeWhere((path, _) => ended.contains(path));
  }

  void _admit(EntryHash entry, EventAdmitted admitted) {
    final EventAdmitted(:conversation, :key, :message) = admitted;
    _events[(conversation, key)] = admitted.event;
    final outside = admitted.within ?? conversation;

    JourneyId journey(JourneyPlacement placement) => switch (placement) {
      InJourney(:final journey) => journey,
      StartsJourney() => _start(entry, outside, admitted.rules!),
    };

    final JourneyPathId? journeyPath;
    switch (admitted.placement) {
      case UnderJourneyPath(journeyPath: final under):
        journeyPath = under;
      case StartsJourneyPath(journey: final placement):
        final path = journeyPath = JourneyPathId.parse(entry.hex)!;
        _journeyPaths[conversation] = path;
        _pathJourneys[path] = journey(placement);
      case IntoJourney(journey: final placement):
        journey(placement);
        journeyPath = null;
    }
    if ((journeyPath, message) case (final path?, final message?)) {
      _messages[(conversation, message)] = path;
    }
  }

  /// Starts the journey [outside] is, named by [entry], under [rules].
  JourneyId _start(EntryHash entry, ConversationId outside, JsonObject rules) {
    final journey = _journeys[outside] = JourneyId.parse(entry.hex)!;
    _rules[journey] = rules;
    return journey;
  }
}
