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
final conversation = ConversationId.parse('teams:19:x;messageid=1')!;
final within = ConversationId.parse('teams:19:x')!;
final key = EventKey.parse('message:1')!;
final from = ActorId.parse('teams:t/p')!;
final message = SourceMessageId.parse('19:x;messageid=1|1')!;

final said = MessageSaid(
  conversation: conversation,
  within: within,
  key: key,
  node: UserSaid(author: from, source: message, text: 'hi'),
);

/// One reading of each case, each reading back as itself.
final readings = <AdmissibleEvent>[
  said,
  MessageChanged(
    conversation: conversation,
    within: within,
    from: from,
    key: key,
    message: message,
    change: const Edited(text: 'hello'),
  ),
  MessageChanged(
    conversation: conversation,
    within: null,
    from: null,
    key: key,
    message: message,
    change: const Deleted(),
  ),
  ConversationJoined.of(
    conversation: within,
    within: null,
    from: from,
    key: key,
    joiners: [from, ActorId.parse('teams:bot')!],
  )!,
  ShownMessageJudged(
    conversation: conversation,
    within: within,
    from: from,
    key: key,
    to: message,
    verdict: ProposedCorrectionVerdict({'note': 'not yet'}),
  ),
];

const rules = JsonObject.of({'tools': 'all'});

EventAdmitted _admitted(AdmittedPlacement placement, DecidedBy by) =>
    EventAdmitted(
      event,
      by: by,
      reading: said,
      placement: placement,
      rules: EventAdmitted.starts(placement) ? rules : null,
      startsTurn: true,
    );

String _text((Kind, Uint8List) entry) => utf8.decode(entry.$2);

void main() {
  test('an admission that starts a journey and its first journey path', () {
    final entry = encodeDecision(
      _admitted(const StartsJourneyPath(StartsJourney()), DecidedBy.rules),
    );
    expect(entry.$1, DecisionEntryKind.admitted);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","reading":{"case":"message-said",'
      '"conversation":"teams:19:x;messageid=1","within":"teams:19:x",'
      '"key":"message:1","node":{"shape":"UserSaid","author":"teams:t/p",'
      '"source":"19:x;messageid=1|1","text":"hi"}},'
      '"startsJourneyPath":true,"startsJourney":true,'
      '"rules":{"tools":"all"},"startsTurn":true}',
    );
  });

  test('a duplicate', () {
    final entry = encodeDecision(
      DuplicateEvent(
        event,
        by: DecidedBy.rules,
        conversation: conversation,
        key: key,
        of: EntryHash.parse(_b)!,
      ),
    );
    expect(entry.$1, DecisionEntryKind.declined);
    expect(
      _text(entry),
      '{"event":"$_a","by":"rules","why":"duplicate-event",'
      '"conversation":"teams:19:x;messageid=1","key":"message:1","of":"$_b"}',
    );
  });

  test('every case reads back as what was written, whoever decided it', () {
    final journey = JourneyId.parse(_b)!;
    final path = JourneyPathId.parse(_c)!;
    for (final by in DecidedBy.values) {
      final decisions = <AdmissionDecision>[
        _admitted(UnderJourneyPath(path), by),
        _admitted(StartsJourneyPath(InJourney(journey)), by),
        _admitted(const StartsJourneyPath(StartsJourney()), by),
        for (final reading in readings)
          EventAdmitted(
            event,
            by: by,
            reading: reading,
            placement: UnderJourneyPath(path),
            startsTurn: reading is MessageSaid ? true : null,
          ),
        EventAdmitted(
          event,
          by: by,
          reading: said,
          placement: UnderJourneyPath(path),
          startsTurn: false,
        ),
        EventAdmitted(
          event,
          by: by,
          reading: readings[3],
          placement: IntoJourney(InJourney(journey)),
        ),
        _admitted(const IntoJourney(StartsJourney()), by),
        JourneyEnded(event, by: by, journey: journey),
        NoReadingForSource(event, by: by),
        ReadingFoundNothing(event, by: by),
        DuplicateEvent(
          event,
          by: by,
          conversation: conversation,
          key: key,
          of: event,
        ),
        ConversationNotTakenIn(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        SaidStartsNoTurn(event, by: by, conversation: conversation, key: key),
        ShownMessageJudgedUnplaced(
          event,
          by: by,
          conversation: conversation,
          key: key,
        ),
        ChangeToUnadmittedMessage(
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
      'case': 'message-said',
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
      'startsTurn': true,
    };
    expect(decodeDecision(DecisionEntryKind.admitted, bytes(good)), isNotNull);
    expect(
      decodeDecision(
        DecisionEntryKind.admitted,
        bytes({...good, 'startsTurn': false}),
      ),
      isNotNull,
    );
    final (joinKind, joinBody) = encodeDecision(
      EventAdmitted(
        event,
        by: DecidedBy.rules,
        reading: readings.whereType<ConversationJoined>().single,
        placement: IntoJourney(InJourney(JourneyId.parse(_b)!)),
      ),
    );
    final join = jsonDecode(utf8.decode(joinBody)) as Map<String, Object?>;
    expect(decodeDecision(joinKind, bytes(join)), isNotNull);
    final bad = <(Kind, Map<String, Object?>)>[
      // Something said must say whether it starts a turn, as a bool.
      (DecisionEntryKind.admitted, {...good}..remove('startsTurn')),
      (DecisionEntryKind.admitted, {...good, 'startsTurn': 'yes'}),
      // Nothing but something said says it.
      (joinKind, {...join, 'startsTurn': true}),
      (DecisionEntryKind.declined, good),
      (DecisionEntryKind.admitted, {...good, 'extra': 1}),
      (DecisionEntryKind.admitted, {...good}..remove('reading')),
      (DecisionEntryKind.admitted, {...good, 'reading': 'message-said'}),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {...reading, 'extra': 1},
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {...reading}..remove('key'),
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {...reading, 'case': 'x'},
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {...reading, 'from': 'teams:p'},
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {...reading, 'within': null},
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {
            ...reading,
            'node': {'shape': 'Edited', 'text': 'hi'},
          },
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {
            'case': 'conversation-joined',
            'conversation': 'teams:c',
            'key': 'k',
            'joiners': <String>[],
          },
        },
      ),
      (
        DecisionEntryKind.admitted,
        {
          ...good,
          'reading': {
            'case': 'shown-message-judged',
            'conversation': 'teams:c',
            'key': 'k',
            'to': 'c|1',
            'verdict': {'shape': 'ApprovedVerdict'},
          },
        },
      ),
      (DecisionEntryKind.admitted, {...good, 'conversation': 'teams:c'}),
      (DecisionEntryKind.admitted, {...good}..remove('by')),
      (DecisionEntryKind.admitted, {...good, 'by': 'nick'}),
      (DecisionEntryKind.admitted, {...good, 'by': null}),
      (DecisionEntryKind.admitted, {...good, 'event': 'nothex'}),
      (DecisionEntryKind.admitted, {...good, 'journey': _b}),
      (
        DecisionEntryKind.admitted,
        {...good}
          ..remove('journeyPath')
          ..addAll({'journey': _b, 'startsJourney': true}),
      ),
      (
        DecisionEntryKind.admitted,
        {...good}
          ..remove('journeyPath')
          ..addAll({'startsJourneyPath': false, 'journey': _b}),
      ),
      (
        DecisionEntryKind.declined,
        {
          'event': _a,
          'by': 'rules',
          'why': 'no-reading-for-source',
          'key': 'k',
        },
      ),
      (
        DecisionEntryKind.declined,
        {'event': _a, 'by': 'rules', 'why': 'never-heard-of-it'},
      ),
      (
        DecisionEntryKind.declined,
        {'event': _a, 'why': 'no-reading-for-source'},
      ),
      (DecisionEntryKind.ended, {'event': _a, 'by': 'rules'}),
      (DecisionEntryKind.ended, {'event': _a, 'by': 'rules', 'journey': 'x'}),
      (
        DecisionEntryKind.ended,
        {'event': _a, 'by': 'rules', 'journey': _b, 'why': 'done'},
      ),
      (DecisionEntryKind.admitted, {'event': _a, 'by': 'rules', 'journey': _b}),
      (
        Kind.parse('event')!,
        {'event': _a, 'by': 'rules', 'why': 'no-reading-for-source'},
      ),
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
    expect(
      decodeDecision(DecisionEntryKind.admitted, bytes(starts)),
      isNotNull,
    );
    for (final json in [
      {
        ...good,
        'rules': {'tools': 'all'},
      },
      {...starts}..remove('rules'),
      {...starts, 'rules': 'all'},
      {...starts, 'rules': null},
      // Something said that starts no turn starts no journey path.
      {...starts, 'startsTurn': false},
    ]) {
      expect(
        decodeDecision(DecisionEntryKind.admitted, bytes(json)),
        isNull,
        reason: '$json',
      );
    }
    expect(
      decodeDecision(DecisionEntryKind.admitted, Uint8List.fromList([0xff])),
      isNull,
    );
  });
}
