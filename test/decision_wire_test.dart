// The decision entry is a wire contract: whatever reads the record reads
// these field names. So this is kept (RULINGS, "Tests prove once": the
// suite keeps wire contracts).
import 'dart:convert';
import 'dart:typed_data';

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_docking_port/is_docking_port.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, JourneyId, JourneyPathId;
import 'package:test/test.dart';

final _a = 'a' * 64, _b = 'b' * 64, _c = 'c' * 64;
final arrival = EntryHash.parse(_a)!;
final conversation = Conversation.parse('teams:19:x;messageid=1')!;
final within = Conversation.parse('teams:19:x')!;
final key = ArrivalKey.parse('message:1')!;
final from = ActorId.parse('teams:t/p')!;
final message = SourceMessageId.parse('19:x;messageid=1|1')!;

Admitted _admitted(Placement placement, DecidedBy by) => Admitted(
  arrival,
  by: by,
  conversation: conversation,
  within: within,
  key: key,
  from: from,
  message: message,
  placement: placement,
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
      '{"arrival":"$_a","by":"rules",'
      '"conversation":"teams:19:x;messageid=1",'
      '"key":"message:1","within":"teams:19:x","from":"teams:t/p",'
      '"message":"19:x;messageid=1|1","startsJourneyPath":true,'
      '"startsJourney":true}',
    );
  });

  test('an admission the person said yes to', () {
    final entry = encodeDecision(
      Admitted(
        arrival,
        by: DecidedBy.person,
        conversation: within,
        within: null,
        key: key,
        from: null,
        message: null,
        placement: const StartsJourneyPath(StartsJourney()),
      ),
    );
    expect(entry.$1, DecisionKind.admitted);
    expect(
      _text(entry),
      '{"arrival":"$_a","by":"person","conversation":"teams:19:x",'
      '"key":"message:1","startsJourneyPath":true,"startsJourney":true}',
    );
  });

  test('a duplicate', () {
    final entry = encodeDecision(
      Duplicate(
        arrival,
        by: DecidedBy.rules,
        conversation: conversation,
        key: key,
        of: EntryHash.parse(_b)!,
      ),
    );
    expect(entry.$1, DecisionKind.declined);
    expect(
      _text(entry),
      '{"arrival":"$_a","by":"rules","why":"duplicate",'
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
        Admitted(
          arrival,
          by: by,
          conversation: within,
          within: null,
          key: key,
          from: null,
          message: null,
          placement: IntoJourney(InJourney(journey)),
        ),
        _admitted(const IntoJourney(StartsJourney()), by),
        Unread(arrival, by: by),
        NotAdmissible(arrival, by: by),
        Duplicate(
          arrival,
          by: by,
          conversation: conversation,
          key: key,
          of: arrival,
        ),
        NotTakenIn(arrival, by: by, conversation: conversation, key: key),
        NotATurn(arrival, by: by, conversation: conversation, key: key),
        RespondsUnplaced(arrival, by: by, conversation: conversation, key: key),
        ChangesUnadmitted(
          arrival,
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
    final good = {
      'arrival': _a,
      'by': 'rules',
      'conversation': 'teams:c',
      'key': 'k',
      'journeyPath': _c,
    };
    expect(decodeDecision(DecisionKind.admitted, bytes(good)), isNotNull);
    final bad = <(Kind, Map<String, Object?>)>[
      (DecisionKind.declined, good),
      (DecisionKind.admitted, {...good, 'extra': 1}),
      (DecisionKind.admitted, {...good}..remove('key')),
      (DecisionKind.admitted, {...good}..remove('by')),
      (DecisionKind.admitted, {...good, 'by': 'nick'}),
      (DecisionKind.admitted, {...good, 'by': null}),
      (DecisionKind.admitted, {...good, 'arrival': 'nothex'}),
      (DecisionKind.admitted, {...good, 'within': 'no-colon'}),
      (DecisionKind.admitted, {...good, 'from': null}),
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
        {'arrival': _a, 'by': 'rules', 'why': 'unread', 'key': 'k'},
      ),
      (
        DecisionKind.declined,
        {'arrival': _a, 'by': 'rules', 'why': 'never-heard-of-it'},
      ),
      (DecisionKind.declined, {'arrival': _a, 'why': 'unread'}),
      (Kind.parse('arrived')!, {'arrival': _a, 'by': 'rules', 'why': 'unread'}),
    ];
    for (final (kind, json) in bad) {
      expect(decodeDecision(kind, bytes(json)), isNull, reason: '$json');
    }
    expect(
      decodeDecision(DecisionKind.admitted, Uint8List.fromList([0xff])),
      isNull,
    );
  });
}
