// The decision entry is a wire contract: whatever reads the record reads
// these field names. So this is kept (RULINGS, "Tests prove once": the
// suite keeps wire contracts).
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show ProposedCorrectionVerdict;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show Deleted, Edited, SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, JourneyId, JourneyPathId;
import 'package:test/test.dart';

final _a = 'a' * 64, _b = 'b' * 64, _c = 'c' * 64;
final event = EntryHash.parse(_a)!;
final conversation = Conversation.parse('teams:19:x;messageid=1')!;
final within = Conversation.parse('teams:19:x')!;
final key = EventKey.parse('message:1')!;
final from = ActorId.parse('teams:t/p')!;
final message = SourceMessageId.parse('19:x;messageid=1|1')!;

final said = Said(
  conversation: conversation,
  within: within,
  key: key,
  node: UserSaid(author: from, source: message, text: 'hi'),
);

/// One reading of each case, each reading back as itself.
final readings = <Admissible>[
  said,
  Changed(
    conversation: conversation,
    within: within,
    from: from,
    key: key,
    message: message,
    change: const Edited(text: 'hello'),
  ),
  Changed(
    conversation: conversation,
    within: null,
    from: null,
    key: key,
    message: message,
    change: const Deleted(),
  ),
  Joined.of(
    conversation: within,
    within: null,
    from: from,
    key: key,
    joiners: [from, ActorId.parse('teams:bot')!],
  )!,
  Judged(
    conversation: conversation,
    within: within,
    from: from,
    key: key,
    to: message,
    verdict: ProposedCorrectionVerdict({'note': 'not yet'}),
  ),
];

const rules = JsonObject.of({'tools': 'all'});

Admitted _admitted(Placement placement, DecidedBy by) => Admitted(
  event,
  by: by,
  reading: said,
  placement: placement,
  rules: Admitted.starts(placement) ? rules : null,
);

String _text((Kind, Uint8List) entry) => utf8.decode(entry.$2);

void main() {
  test('an admission that starts a journey and its first journey path', () {
    final entry = encodeDecision(
      _admitted(const StartsJourneyPath(StartsJourney()), DecidedBy.rules),
    );
    expect(entry.$1, DecisionKind.admitted);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","reading":{"case":"said",'
      '"conversation":"teams:19:x;messageid=1","within":"teams:19:x",'
      '"key":"message:1","node":{"shape":"UserSaid","author":"teams:t/p",'
      '"source":"19:x;messageid=1|1","text":"hi"}},'
      '"startsJourneyPath":true,"startsJourney":true,'
      '"rules":{"tools":"all"}}',
    );
  });

  test('a duplicate', () {
    final entry = encodeDecision(
      Duplicate(
        event,
        by: DecidedBy.rules,
        conversation: conversation,
        key: key,
        of: EntryHash.parse(_b)!,
      ),
    );
    expect(entry.$1, DecisionKind.declined);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","why":"duplicate",'
      '"conversation":"teams:19:x;messageid=1","key":"message:1","of":"$_b"}',
    );
  });

  test('every case reads back as what was written, whoever decided it', () {
    final journey = JourneyId.parse(_b)!;
    final path = JourneyPathId.parse(_c)!;
    for (final by in DecidedBy.values) {
      final decisions = <Decision>[
        _admitted(Under(path), by),
        _admitted(StartsJourneyPath(InJourney(journey)), by),
        _admitted(const StartsJourneyPath(StartsJourney()), by),
        for (final reading in readings)
          Admitted(event, by: by, reading: reading, placement: Under(path)),
        Admitted(
          event,
          by: by,
          reading: readings[3],
          placement: IntoJourney(InJourney(journey)),
        ),
        _admitted(const IntoJourney(StartsJourney()), by),
        Ended(event, by: by, journey: journey),
        Unread(event, by: by),
        NotAdmissible(event, by: by),
        Duplicate(
          event,
          by: by,
          conversation: conversation,
          key: key,
          of: event,
        ),
        NotTakenIn(event, by: by, conversation: conversation, key: key),
        NotATurn(event, by: by, conversation: conversation, key: key),
        JudgedUnplaced(event, by: by, conversation: conversation, key: key),
        ChangesUnadmitted(
          event,
          by: by,
          conversation: conversation,
          key: key,
          message: message,
        ),
      ];
      for (final decision in decisions) {
        final (kind, body) = encodeDecision(decision);
        final back = decodeDecision(kind, body);
        expect(back, isNotNull, reason: utf8.decode(body));
        expect(back.runtimeType, decision.runtimeType);
        expect(_text(encodeDecision(back!)), utf8.decode(body));
      }
    }
  });

  test('anything else reads as null', () {
    Uint8List bytes(Map<String, Object?> json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final reading = {
      'case': 'said',
      'conversation': 'teams:c',
      'key': 'k',
      'node': {
        'shape': 'UserSaid',
        'author': 'teams:p',
        'source': 'c|1',
        'text': 'hi',
      },
    };
    final good = {
      'event': _a,
      'by': 'rules',
      'reading': reading,
      'journeyPath': _c,
    };
    expect(decodeDecision(DecisionKind.admitted, bytes(good)), isNotNull);
    final bad = <(Kind, Map<String, Object?>)>[
      (DecisionKind.declined, good),
      (DecisionKind.admitted, {...good, 'extra': 1}),
      (DecisionKind.admitted, {...good}..remove('reading')),
      (DecisionKind.admitted, {...good, 'reading': 'said'}),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {...reading, 'extra': 1},
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {...reading}..remove('key'),
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {...reading, 'case': 'x'},
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {...reading, 'from': 'teams:p'},
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {...reading, 'within': null},
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {
            ...reading,
            'node': {'shape': 'Edited', 'text': 'hi'},
          },
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {
            'case': 'joined',
            'conversation': 'teams:c',
            'key': 'k',
            'joiners': <String>[],
          },
        },
      ),
      (
        DecisionKind.admitted,
        {
          ...good,
          'reading': {
            'case': 'judged',
            'conversation': 'teams:c',
            'key': 'k',
            'to': 'c|1',
            'verdict': {'shape': 'ApprovedVerdict'},
          },
        },
      ),
      (DecisionKind.admitted, {...good, 'conversation': 'teams:c'}),
      (DecisionKind.admitted, {...good}..remove('by')),
      (DecisionKind.admitted, {...good, 'by': 'nick'}),
      (DecisionKind.admitted, {...good, 'by': null}),
      (DecisionKind.admitted, {...good, 'event': 'nothex'}),
      (DecisionKind.admitted, {...good, 'journey': _b}),
      (
        DecisionKind.admitted,
        {...good}
          ..remove('journeyPath')
          ..addAll({'journey': _b, 'startsJourney': true}),
      ),
      (
        DecisionKind.admitted,
        {...good}
          ..remove('journeyPath')
          ..addAll({'startsJourneyPath': false, 'journey': _b}),
      ),
      (
        DecisionKind.declined,
        {'event': _a, 'by': 'rules', 'why': 'unread', 'key': 'k'},
      ),
      (
        DecisionKind.declined,
        {'event': _a, 'by': 'rules', 'why': 'never-heard-of-it'},
      ),
      (DecisionKind.declined, {'event': _a, 'why': 'unread'}),
      (DecisionKind.ended, {'event': _a, 'by': 'rules'}),
      (DecisionKind.ended, {'event': _a, 'by': 'rules', 'journey': 'x'}),
      (
        DecisionKind.ended,
        {'event': _a, 'by': 'rules', 'journey': _b, 'why': 'done'},
      ),
      (DecisionKind.admitted, {'event': _a, 'by': 'rules', 'journey': _b}),
      (Kind.parse('event')!, {'event': _a, 'by': 'rules', 'why': 'unread'}),
    ];
    for (final (kind, json) in bad) {
      expect(decodeDecision(kind, bytes(json)), isNull, reason: '$json');
    }
    final starts = {
      ...good,
      'startsJourneyPath': true,
      'startsJourney': true,
      'rules': {'tools': 'all'},
    }..remove('journeyPath');
    expect(decodeDecision(DecisionKind.admitted, bytes(starts)), isNotNull);
    for (final json in [
      {
        ...good,
        'rules': {'tools': 'all'},
      },
      {...starts}..remove('rules'),
      {...starts, 'rules': 'all'},
      {...starts, 'rules': null},
    ]) {
      expect(
        decodeDecision(DecisionKind.admitted, bytes(json)),
        isNull,
        reason: '$json',
      );
    }
    expect(
      decodeDecision(DecisionKind.admitted, Uint8List.fromList([0xff])),
      isNull,
    );
  });
}
