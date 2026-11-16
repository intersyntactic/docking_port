/// A decision as the record entry the docking port sends, and back: the
/// JSON its class docs give, read strictly, since it is our own wire.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, JourneyId, JourneyPathId;

import 'decision.dart';
import 'reading.dart';

/// [decision] as the entry the docking port sends: its kind, and its body.
(Kind, Uint8List) encodeDecision(Decision decision) {
  final json = <String, Object?>{'arrival': decision.arrival.hex};
  switch (decision) {
    case Admitted():
      json
        ..['conversation'] = decision.conversation.value
        ..['key'] = decision.key.value;
      if (decision.within case final within?) json['within'] = within.value;
      if (decision.from case final from?) json['from'] = from.value;
      if (decision.message case final message?) json['message'] = message.value;
      switch (decision.placement) {
        case Under(:final journeyPath):
          json['journeyPath'] = journeyPath.hex;
        case StartsJourneyPath(:final journey):
          json['startsJourneyPath'] = true;
          _journey(json, journey);
        case IntoJourney(:final journey):
          _journey(json, journey);
      }
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
  final kind = decision is Admitted
      ? DecisionKind.admitted
      : DecisionKind.declined;
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
  RespondsUnplaced() => 'responds-unplaced',
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
  final arrival = _read(json['arrival'], EntryHash.parse);
  if (arrival == null) return null;
  if (kind == DecisionKind.admitted) return _admitted(arrival, json);
  if (kind == DecisionKind.declined) return _declined(arrival, json);
  return null;
}

Admitted? _admitted(EntryHash arrival, Map<String, Object?> json) {
  final conversation = _read(json['conversation'], Conversation.parse);
  final key = _read(json['key'], ArrivalKey.parse);
  if (conversation == null || key == null) return null;
  final fields = {'arrival', 'conversation', 'key'};

  // An optional field: absent, or present and well formed.
  T? optional<T extends Object>(String name, T? Function(String) parse) {
    if (!json.containsKey(name)) return null;
    fields.add(name);
    return _read(json[name], parse);
  }

  final within = optional('within', Conversation.parse);
  final from = optional('from', ActorId.parse);
  final message = optional('message', SourceMessageId.parse);
  // A field that is present but malformed is in [fields] and read as null,
  // so the two counts differ.
  if (fields.length != 3 + [within, from, message].nonNulls.length) {
    return null;
  }

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
  if (json.length != fields.length) return null;
  return Admitted(
    arrival,
    conversation: conversation,
    within: within,
    key: key,
    from: from,
    message: message,
    placement: placement,
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

Declined? _declined(EntryHash arrival, Map<String, Object?> json) {
  final why = json['why'];
  if (why is! String) return null;
  if (why == 'unread' || why == 'not-admissible') {
    if (json.length != 2) return null;
    return why == 'unread' ? Unread(arrival) : NotAdmissible(arrival);
  }
  final conversation = _read(json['conversation'], Conversation.parse);
  final key = _read(json['key'], ArrivalKey.parse);
  if (conversation == null || key == null) return null;
  switch (why) {
    case 'duplicate':
      final of = _read(json['of'], EntryHash.parse);
      if (of == null || json.length != 5) return null;
      return Duplicate(arrival, conversation: conversation, key: key, of: of);
    case 'changes-unadmitted':
      final message = _read(json['message'], SourceMessageId.parse);
      if (message == null || json.length != 5) return null;
      return ChangesUnadmitted(
        arrival,
        conversation: conversation,
        key: key,
        message: message,
      );
    case 'not-taken-in' || 'not-a-turn' || 'responds-unplaced':
      if (json.length != 4) return null;
      return switch (why) {
        'not-taken-in' => NotTakenIn(
          arrival,
          conversation: conversation,
          key: key,
        ),
        'not-a-turn' => NotATurn(arrival, conversation: conversation, key: key),
        _ => RespondsUnplaced(arrival, conversation: conversation, key: key),
      };
    default:
      return null;
  }
}

/// [value] parsed by [parse] when it is a string; null otherwise.
T? _read<T>(Object? value, T? Function(String) parse) =>
    value is String ? parse(value) : null;
