/// A reading as the `admitted` entry carries it, and back, read strictly,
/// since it is our own wire.
///
/// The nodes inside travel in their own packages' map form,
/// `{"shape": <class name>, ...its fields}`, each under a field of its own,
/// so this reads each with its own package's decoder and never looks at a
/// node's fields itself.
library;

import 'package:checked_json/checked_json.dart';
import 'package:is_annotation_shapes/is_annotation_shapes.dart' show Verdict;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid, WhatChanged;
import 'package:is_shapes/is_shapes.dart' show ActorId;

import 'reading.dart';

/// Every node shape a reading can carry, by the field it travels in, as
/// each node's package names them. A `shape` is one namespace across every
/// package whose nodes travel in map form, so no two of these may share a
/// name (Nick, 16 Nov: the docking station checks names).
const readingNodeShapes = <String, Set<String>>{
  'node': {UserSaid.shapeName},
  'change': WhatChanged.shapeNames,
  'verdict': Verdict.shapeNames,
};

/// [reading] as JSON:
///
///     {"case": <case>, "conversation": <id>, "within": <id>?,
///      "key": <key>, ...the case's own fields}
///
/// `<case>` and its fields are `said`, with `"node"`, a [UserSaid];
/// `changed`, with `"from"?`, `"message"` and `"change"`, a [WhatChanged];
/// `joined`, with `"from"?` and `"joiners"`; `judged`, with `"from"`,
/// `"to"` and `"verdict"`, a [Verdict].
JsonObject encodeReading(Admissible reading) => JsonObject.of({
  'case': _case(reading),
  'conversation': reading.conversation.value,
  'within': ?reading.within?.value,
  'key': reading.key.value,
  ...switch (reading) {
    Said(:final node) => {'node': node.toJson()},
    Changed(:final from, :final message, :final change) => {
      'from': ?from?.value,
      'message': message.value,
      'change': change.toJson(),
    },
    Joined(:final from, :final joiners) => {
      'from': ?from?.value,
      'joiners': [for (final joiner in joiners) joiner.value],
    },
    Judged(:final from, :final to, :final verdict) => {
      'from': from.value,
      'to': to.value,
      'verdict': verdict.toJson(),
    },
  },
});

String _case(Admissible reading) => switch (reading) {
  Said() => 'said',
  Changed() => 'changed',
  Joined() => 'joined',
  Judged() => 'judged',
};

/// [json] read back as the reading [encodeReading] wrote. A
/// [FormatException] for anything it doesn't write: an unknown case, a
/// field missing, extra or malformed, a node its package won't read.
Admissible decodeReading(JsonObject json) {
  final conversation = _parse(json, 'conversation', Conversation.parse);
  final within = json.has('within')
      ? _parse(json, 'within', Conversation.parse)
      : null;
  final key = _parse(json, 'key', EventKey.parse);
  ActorId? from() =>
      json.has('from') ? _parse(json, 'from', ActorId.parse) : null;

  final (reading, fields) = switch (json.string('case')) {
    'said' => (
      Said(
        conversation: conversation,
        within: within,
        key: key,
        node: UserSaid.fromJson(json.object('node')),
      ),
      const {'node'},
    ),
    'changed' => (
      Changed(
        conversation: conversation,
        within: within,
        from: from(),
        key: key,
        message: _parse(json, 'message', SourceMessageId.parse),
        change: WhatChanged.fromJson(json.object('change')),
      ),
      const {'from', 'message', 'change'},
    ),
    'joined' => (
      Joined.of(
            conversation: conversation,
            within: within,
            from: from(),
            key: key,
            joiners: [
              for (final joiner in json.strings('joiners'))
                ActorId.parse(joiner) ??
                    (throw JsonFieldException('joiners', 'actor ids')),
            ],
          ) ??
          (throw JsonFieldException('joiners', 'a list of one or more')),
      const {'from', 'joiners'},
    ),
    'judged' => (
      Judged(
        conversation: conversation,
        within: within,
        from: _parse(json, 'from', ActorId.parse),
        key: key,
        to: _parse(json, 'to', SourceMessageId.parse),
        verdict: Verdict.fromJson(json.object('verdict')),
      ),
      const {'from', 'to', 'verdict'},
    ),
    final other => throw FormatException('`case` is not a reading: $other'),
  };
  for (final field in json.keys) {
    if (!{'case', 'conversation', 'within', 'key', ...fields}.contains(field)) {
      throw FormatException('`$field` is not a field of a reading');
    }
  }
  return reading;
}

/// [json]'s [field], a string, parsed by [parse]; a [JsonFieldException]
/// when it is absent, not a string, or [parse] refuses it.
T _parse<T extends Object>(
  JsonObject json,
  String field,
  T? Function(String) parse,
) =>
    parse(json.string(field)) ??
    (throw JsonFieldException(field, 'a well-formed ${T.toString()}'));
