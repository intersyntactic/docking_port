/// Deciding one arrival: whether it comes in, and where it goes.
library;

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;

import 'decided.dart';
import 'decision.dart';
import 'reading.dart';
import 'rules.dart';

/// What the docking port decides about the `arrived` entry [arrival], read
/// by its module's reading as [reading], given everything [decided] so
/// far. [reading] is null when no reading takes the arrival's source, or
/// its body is not what a relay records.
///
/// In order: an event decided already is a [Duplicate]. A change goes
/// where the message it changes went, and a response under its
/// conversation's journey path. A join goes into its journey, and
/// something said under its conversation's journey path, or a new one
/// that the turn rule lets it start. A journey not yet started is started
/// only when [journeys] takes it in.
Decision decide(
  EntryHash arrival,
  Reading? reading,
  Decided decided, {
  required JourneyRule journeys,
  required TurnRule turns,
}) {
  final Admissible event;
  switch (reading) {
    case null:
      return Unread(arrival);
    case NothingToAdmit():
      return NotAdmissible(arrival);
    case Admissible():
      event = reading;
  }
  final Admissible(:conversation, :key) = event;
  if (decided.decidedAt(conversation, key) case final first?) {
    return Duplicate(arrival, conversation: conversation, key: key, of: first);
  }

  Admitted admit(Placement placement, {SourceMessageId? message}) => Admitted(
    arrival,
    conversation: conversation,
    within: event.within,
    key: key,
    from: event.from,
    message: message,
    placement: placement,
  );

  switch (event) {
    case Changed(:final message):
      return switch (decided.journeyPathOfMessage(conversation, message)) {
        final path? => admit(Under(path), message: message),
        null => ChangesUnadmitted(
          arrival,
          conversation: conversation,
          key: key,
          message: message,
        ),
      };
    case Responded(:final to):
      return switch (decided.journeyPathOf(conversation)) {
        final path? => admit(Under(path), message: to),
        null => RespondsUnplaced(arrival, conversation: conversation, key: key),
      };
    case Joined():
      return switch (_journey(event, decided, journeys)) {
        final journey? => admit(IntoJourney(journey)),
        null => NotTakenIn(arrival, conversation: conversation, key: key),
      };
    case Said():
      final Placement placement;
      if (decided.journeyPathOf(conversation) case final path?) {
        placement = Under(path);
      } else if (_journey(event, decided, journeys) case final journey?) {
        placement = StartsJourneyPath(journey);
      } else {
        return NotTakenIn(arrival, conversation: conversation, key: key);
      }
      return turns.startsTurn(event, placement)
          ? admit(placement, message: event.message)
          : NotATurn(arrival, conversation: conversation, key: key);
  }
}

/// The journey [first]'s conversation goes in: the journey of what it sits
/// within (or of itself, when it sits within nothing) when that has
/// started; a new one when [rule] takes it in; null when it doesn't.
JourneyPlacement? _journey(
  Admissible first,
  Decided decided,
  JourneyRule rule,
) => switch (decided.journeyOf(first.within ?? first.conversation)) {
  final journey? => InJourney(journey),
  null => rule.takesIn(first) ? const StartsJourney() : null,
};
