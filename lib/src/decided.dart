/// What the docking port has decided, rebuilt from its own decisions
/// alone, read back from the record in order (RULINGS: which conversation
/// is under which journey path "is rebuilt by reading its own decisions
/// back, not by working them out again").
library;

import 'package:is_airlock_api/is_airlock_api.dart' show JourneyPathId;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show JourneyId;

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
abstract interface class Decided {
  /// The last decision: what the next one follows. Null before the first.
  EntryHash? get tip;

  /// Whether [arrival] has been decided.
  bool has(EntryHash arrival);

  /// The arrival the event [key] in [conversation] was decided at, either
  /// way. Null when it hasn't been.
  EntryHash? decidedAt(Conversation conversation, ArrivalKey key);

  /// The journey path [conversation] is under. Null when it is under none
  /// yet.
  JourneyPathId? journeyPathOf(Conversation conversation);

  /// The journey [outside] is: a conversation others sit within, such as a
  /// channel, or one that sits within nothing, such as a chat. Null before
  /// it starts.
  JourneyId? journeyOf(Conversation outside);

  /// The journey path the message [message] in [conversation] was admitted
  /// under: where a change to it goes. Null when it was never admitted.
  JourneyPathId? journeyPathOfMessage(
    Conversation conversation,
    SourceMessageId message,
  );

  /// Takes in [decision], recorded at [entry]. An [Admitted] that starts a
  /// journey path or a journey names it by [entry].
  void take(EntryHash entry, Decision decision);
}
