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
(Kind, Uint8List) encodeDecision(Decision decision) {
  final json = <String, Object?>{
    'event': decision.event.hex,
    'by': decision.by.name,
  };
  switch (decision) {
    case Admitted():
      json['reading'] = encodeReading(decision.reading);
      switch (decision.placement) {
        case Under(:final journeyPath):
          json['journeyPath'] = journeyPath.hex;
        case StartsJourneyPath(:final journey):
          json['startsJourneyPath'] = true;
          _journey(json, journey);
        case IntoJourney(:final journey):
          _journey(json, journey);
      }
      if (decision.rules case final rules?) json['rules'] = rules;
    case Ended(:final journey):
      json['journey'] = journey.hex;
    case Declined():
      json['why'] = _why(decision);
      if (decision case DeclinedEvent(:final conversation, :final key)) {
        json
          ..['conversation'] = conversation.value
          ..['key'] = key.value;
      }
      switch (decision) {
        case Duplicate(:final of):
          json['of'] = of.hex;
        case ChangesUnadmitted(:final message):
          json['message'] = message.value;
        case _:
          break;
      }
  }
  final kind = switch (decision) {
    Admitted() => DecisionKind.admitted,
    Declined() => DecisionKind.declined,
    Ended() => DecisionKind.ended,
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

String _why(Declined declined) => switch (declined) {
  Unread() => 'unread',
  NotAdmissible() => 'not-admissible',
  Duplicate() => 'duplicate',
  NotTakenIn() => 'not-taken-in',
  NotATurn() => 'not-a-turn',
  JudgedUnplaced() => 'judged-unplaced',
  ChangesUnadmitted() => 'changes-unadmitted',
};

/// The entry of [kind] with [body], read back as the decision it holds.
/// Null for anything [encodeDecision] doesn't write, an extra field
/// included: it is our own wire, read strictly.
Decision? decodeDecision(Kind kind, Uint8List body) {
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
  if (kind == DecisionKind.admitted) return _admitted(event, by, json);
  if (kind == DecisionKind.declined) return _declined(event, by, json);
  if (kind == DecisionKind.ended) {
    final journey = _read(json['journey'], JourneyId.parse);
    if (journey == null || json.length != 3) return null;
    return Ended(event, by: by, journey: journey);
  }
  return null;
}

/// The [DecidedBy] named [name]; null for any other name.
DecidedBy? _decidedBy(String name) => DecidedBy.values.asNameMap()[name];

Admitted? _admitted(EntryHash event, DecidedBy by, Map<String, Object?> json) {
  final Admissible reading;
  try {
    reading = decodeReading(
      JsonObject.parse(json['reading']) ??
          (throw const FormatException('`reading` is not an object')),
    );
  } on FormatException {
    return null;
  }
  final fields = {'event', 'by', 'reading'};

  final Placement placement;
  if (json.containsKey('journeyPath')) {
    final path = _read(json['journeyPath'], JourneyPathId.parse);
    if (path == null) return null;
    fields.add('journeyPath');
    placement = Under(path);
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
  if (json.length != fields.length) return null;
  if ((rules != null) != Admitted.starts(placement)) return null;
  return Admitted(
    event,
    by: by,
    reading: reading,
    placement: placement,
    rules: rules,
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

Declined? _declined(EntryHash event, DecidedBy by, Map<String, Object?> json) {
  final why = json['why'];
  if (why is! String) return null;
  if (why == 'unread' || why == 'not-admissible') {
    if (json.length != 3) return null;
    return why == 'unread'
        ? Unread(event, by: by)
        : NotAdmissible(event, by: by);
  }
  final conversation = _read(json['conversation'], Conversation.parse);
  final key = _read(json['key'], EventKey.parse);
  if (conversation == null || key == null) return null;
  switch (why) {
    case 'duplicate':
      final of = _read(json['of'], EntryHash.parse);
      if (of == null || json.length != 6) return null;
      return Duplicate(
        event,
        by: by,
        conversation: conversation,
        key: key,
        of: of,
      );
    case 'changes-unadmitted':
      final message = _read(json['message'], SourceMessageId.parse);
      if (message == null || json.length != 6) return null;
      return ChangesUnadmitted(
        event,
        by: by,
        conversation: conversation,
        key: key,
        message: message,
      );
    case 'not-taken-in' || 'not-a-turn' || 'judged-unplaced':
      if (json.length != 5) return null;
      return switch (why) {
        'not-taken-in' => NotTakenIn(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        'not-a-turn' => NotATurn(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        _ => JudgedUnplaced(
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
