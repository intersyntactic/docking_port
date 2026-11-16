/// Deciding one event: whether it comes in, and where it goes.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show DecidedBy;

import 'decided.dart';
import 'decision.dart';
import 'reading.dart';
import 'rules.dart';

/// What the docking station decides about the event recorded at [event], read
/// by its module's reading as [reading], given everything [decided] so
/// far. [reading] is null when no reading takes the event's source, or its
/// body is not what a relay records.
///
/// In order: an event whose key was decided already is a [Duplicate]. A
/// change goes where the message it changes went, and a verdict under its
/// conversation's journey path. A join goes into its journey, and
/// something said under its conversation's journey path, or a new one
/// that the turn rule lets it start. A journey not yet started is started
/// only when [journeys] takes it in.
///
/// Every decision it makes is [DecidedBy.rules]: nothing here asks the
/// person.
Decision decide(
  EntryHash event,
  Reading? reading,
  Decided decided, {
  required JourneyRule journeys,
  required TurnRule turns,
}) {
  const by = DecidedBy.rules;
  final Admissible admissible;
  switch (reading) {
    case null:
      return Unread(event, by: by);
    case NothingToAdmit():
      return NotAdmissible(event, by: by);
    case Admissible():
      admissible = reading;
  }
  final Admissible(:conversation, :key) = admissible;
  if (decided.decidedAt(conversation, key) case final first?) {
    return Duplicate(
      event,
      by: by,
      conversation: conversation,
      key: key,
      of: first,
    );
  }

  Admitted admit(Placement placement, [JsonObject? rules]) => Admitted(
    event,
    by: by,
    reading: admissible,
    placement: placement,
    rules: rules,
  );

  switch (admissible) {
    case Changed(:final message):
      return switch (decided.journeyPathOfMessage(conversation, message)) {
        final path? => admit(Under(path)),
        null => ChangesUnadmitted(
          event,
          by: by,
          conversation: conversation,
          key: key,
          message: message,
        ),
      };
    case Judged():
      return switch (decided.journeyPathOf(conversation)) {
        final path? => admit(Under(path)),
        null => JudgedUnplaced(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
      };
    case Joined():
      return switch (_journey(admissible, decided, journeys)) {
        (InJourney() && final journey, _) => admit(IntoJourney(journey)),
        (final journey, final rules) => admit(IntoJourney(journey), rules),
        null => NotTakenIn(event, by: by, conversation: conversation, key: key),
      };
    case Said():
      final Placement placement;
      JsonObject? rules;
      if (decided.journeyPathOf(conversation) case final path?) {
        placement = Under(path);
      } else if (_journey(admissible, decided, journeys)
          case (final journey, final journeyRules)?) {
        placement = StartsJourneyPath(journey);
        rules = journeyRules;
      } else {
        return NotTakenIn(event, by: by, conversation: conversation, key: key);
      }
      return turns.startsTurn(admissible, placement)
          ? admit(placement, rules)
          : NotATurn(event, by: by, conversation: conversation, key: key);
  }
}

/// The journey [first]'s conversation goes in, with its rules: the
/// journey of what it sits within (or of itself, when it sits within
/// nothing) when that has started; a new one when [rule] takes it in; null
/// when it doesn't.
(JourneyPlacement, JsonObject)? _journey(
  Admissible first,
  Decided decided,
  JourneyRule rule,
) => switch (decided.journeyOf(first.within ?? first.conversation)) {
  final journey? => (InJourney(journey), decided.rulesOf(journey)),
  null => switch (rule.takeIn(first)) {
    final rules? => (const StartsJourney(), rules),
    null => null,
  },
};
