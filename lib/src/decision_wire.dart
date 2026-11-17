/// A decision as the record entry the docking station sends, and back: the
/// JSON its class docs give, read strictly, since it is our own wire.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, JourneyId, JourneyPathId;

import 'decision.dart';
import 'reading.dart';
import 'reading_wire.dart';

/// [decision] as the entry the docking station sends: its kind, and its body.
(Kind, Uint8List) encodeDecision(AdmissionDecision decision) {
  final json = <String, Object?>{
    'event': decision.event.hex,
    'by': decision.by.name,
  };
  switch (decision) {
    case EventAdmitted():
      json['reading'] = encodeReading(decision.reading);
      switch (decision.placement) {
        case UnderJourneyPath(:final journeyPath):
          json['journeyPath'] = journeyPath.hex;
        case StartsJourneyPath(:final journey):
          json['startsJourneyPath'] = true;
          _journey(json, journey);
        case IntoJourney(:final journey):
          _journey(json, journey);
      }
      if (decision.rules case final rules?) json['rules'] = rules;
      if (decision.startsTurn case final startsTurn?) {
        json['startsTurn'] = startsTurn;
      }
    case JourneyEnded(:final journey):
      json['journey'] = journey.hex;
    case EventDeclined():
      json['why'] = _why(decision);
      if (decision case DeclinedKeyedEvent(:final conversation, :final key)) {
        json
          ..['conversation'] = conversation.value
          ..['key'] = key.value;
      }
      switch (decision) {
        case DuplicateEvent(:final of):
          json['of'] = of.hex;
        case ChangeToUnadmittedMessage(:final message):
          json['message'] = message.value;
        case _:
          break;
      }
  }
  final kind = switch (decision) {
    EventAdmitted() => DecisionEntryKind.admitted,
    EventDeclined() => DecisionEntryKind.declined,
    JourneyEnded() => DecisionEntryKind.journeyEnded,
  };
  return (kind, Uint8List.fromList(utf8.encode(jsonEncode(json))));
}

void _journey(Map<String, Object?> json, JourneyPlacement journey) {
  switch (journey) {
    case InJourney(:final journey):
      json['journey'] = journey.hex;
    case StartsJourney():
      json['startsJourney'] = true;
  }
}

String _why(EventDeclined declined) => switch (declined) {
  NoReadingForSource() => 'no-reading-for-source',
  ReadingFoundNothing() => 'reading-found-nothing',
  DuplicateEvent() => 'duplicate-event',
  ConversationNotTakenIn() => 'conversation-not-taken-in',
  SaidStartsNoTurn() => 'said-starts-no-turn',
  ShownMessageJudgedUnplaced() => 'shown-message-judged-unplaced',
  ChangeToUnadmittedMessage() => 'change-to-unadmitted-message',
};

/// The entry of [kind] with [body], read back as the decision it holds.
/// Null for anything [encodeDecision] doesn't write, an extra field
/// included: it is our own wire, read strictly.
AdmissionDecision? decodeDecision(Kind kind, Uint8List body) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final event = _read(json['event'], EntryHash.parse);
  final by = _read(json['by'], _decidedBy);
  if (event == null || by == null) return null;
  if (kind == DecisionEntryKind.admitted) return _admitted(event, by, json);
  if (kind == DecisionEntryKind.declined) return _declined(event, by, json);
  if (kind == DecisionEntryKind.journeyEnded) {
    final journey = _read(json['journey'], JourneyId.parse);
    if (journey == null || json.length != 3) return null;
    return JourneyEnded(event, by: by, journey: journey);
  }
  return null;
}

/// The [DecidedBy] named [name]; null for any other name.
DecidedBy? _decidedBy(String name) => DecidedBy.values.asNameMap()[name];

EventAdmitted? _admitted(
  EntryHash event,
  DecidedBy by,
  Map<String, Object?> json,
) {
  final AdmissibleEvent reading;
  try {
    reading = decodeReading(
      JsonObject.parse(json['reading']) ??
          (throw const FormatException('`reading` is not an object')),
    );
  } on FormatException {
    return null;
  }
  final fields = {'event', 'by', 'reading'};

  final AdmittedPlacement placement;
  if (json.containsKey('journeyPath')) {
    final path = _read(json['journeyPath'], JourneyPathId.parse);
    if (path == null) return null;
    fields.add('journeyPath');
    placement = UnderJourneyPath(path);
  } else {
    final journey = _readJourney(json, fields);
    if (journey == null) return null;
    if (json.containsKey('startsJourneyPath')) {
      if (json['startsJourneyPath'] != true) return null;
      fields.add('startsJourneyPath');
      placement = StartsJourneyPath(journey);
    } else {
      placement = IntoJourney(journey);
    }
  }
  JsonObject? rules;
  if (json.containsKey('rules')) {
    rules = JsonObject.parse(json['rules']);
    if (rules == null) return null;
    fields.add('rules');
  }
  bool? startsTurn;
  if (json.containsKey('startsTurn')) {
    if (json['startsTurn'] case final bool value) {
      startsTurn = value;
    } else {
      return null;
    }
    fields.add('startsTurn');
  }
  if (json.length != fields.length) return null;
  if ((rules != null) != EventAdmitted.starts(placement)) return null;
  if ((startsTurn != null) != (reading is MessageSaid)) return null;
  if (placement is StartsJourneyPath && startsTurn == false) return null;
  return EventAdmitted(
    event,
    by: by,
    reading: reading,
    placement: placement,
    rules: rules,
    startsTurn: startsTurn,
  );
}

JourneyPlacement? _readJourney(Map<String, Object?> json, Set<String> fields) {
  final inJourney = json.containsKey('journey');
  final starts = json.containsKey('startsJourney');
  if (inJourney == starts) return null;
  if (inJourney) {
    final journey = _read(json['journey'], JourneyId.parse);
    if (journey == null) return null;
    fields.add('journey');
    return InJourney(journey);
  }
  if (json['startsJourney'] != true) return null;
  fields.add('startsJourney');
  return const StartsJourney();
}

EventDeclined? _declined(
  EntryHash event,
  DecidedBy by,
  Map<String, Object?> json,
) {
  final why = json['why'];
  if (why is! String) return null;
  if (why == 'no-reading-for-source' || why == 'reading-found-nothing') {
    if (json.length != 3) return null;
    return why == 'no-reading-for-source'
        ? NoReadingForSource(event, by: by)
        : ReadingFoundNothing(event, by: by);
  }
  final conversation = _read(json['conversation'], ConversationId.parse);
  final key = _read(json['key'], EventKey.parse);
  if (conversation == null || key == null) return null;
  switch (why) {
    case 'duplicate-event':
      final of = _read(json['of'], EntryHash.parse);
      if (of == null || json.length != 6) return null;
      return DuplicateEvent(
        event,
        by: by,
        conversation: conversation,
        key: key,
        of: of,
      );
    case 'change-to-unadmitted-message':
      final message = _read(json['message'], SourceMessageId.parse);
      if (message == null || json.length != 6) return null;
      return ChangeToUnadmittedMessage(
        event,
        by: by,
        conversation: conversation,
        key: key,
        message: message,
      );
    case 'conversation-not-taken-in' ||
        'said-starts-no-turn' ||
        'shown-message-judged-unplaced':
      if (json.length != 5) return null;
      return switch (why) {
        'conversation-not-taken-in' => ConversationNotTakenIn(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        'said-starts-no-turn' => SaidStartsNoTurn(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        _ => ShownMessageJudgedUnplaced(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
      };
    default:
      return null;
  }
}

/// [value] parsed by [parse] when it is a string; null otherwise.
T? _read<T>(Object? value, T? Function(String) parse) =>
    value is String ? parse(value) : null;
