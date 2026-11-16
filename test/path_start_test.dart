// readPathStart reads the `admitted` wire on its own, apart from
// decodeDecision, so the airlock never decodes a reading. Two readers of
// one wire can drift apart: this holds them together over every admitted
// case the docking station writes, and holds the narrow reader as strict as
// the full one everywhere outside `reading`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_docking_station/path_start.dart';
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, JourneyId, JourneyPathId;
import 'package:test/test.dart';

import 'decision_wire_test.dart' show event, readings, rules, said;

final _b = 'b' * 64, _c = 'c' * 64;

/// [decision] as the record holds it: the header its ids are hashed with,
/// then its body.
Uint8List _entry(AdmissionDecision decision, {String follows = '-'}) {
  final (kind, body) = encodeDecision(decision);
  return Uint8List.fromList([...utf8.encode('$kind\n$follows\n'), ...body]);
}

Uint8List _raw(String kind, Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode('$kind\n-\n${jsonEncode(json)}'));

AdmittedPathEntry<JsonObject> _read(Uint8List entry) =>
    readPathStart(entry, rules: JsonObject.parse);

void main() {
  test('agrees with decodeDecision on every admitted case', () {
    final journey = JourneyId.parse(_b)!;
    final path = JourneyPathId.parse(_c)!;
    EventAdmitted admitted(
      AdmissibleEvent reading,
      AdmittedPlacement placement, {
      bool startsTurn = true,
    }) => EventAdmitted(
      event,
      by: DecidedBy.person,
      reading: reading,
      placement: placement,
      rules: EventAdmitted.starts(placement) ? rules : null,
      startsTurn: reading is MessageSaid ? startsTurn : null,
    );
    final decisions = [
      for (final reading in readings)
        if (reading is ConversationJoined) ...[
          admitted(reading, IntoJourney(InJourney(journey))),
          admitted(reading, const IntoJourney(StartsJourney())),
        ] else
          admitted(reading, UnderJourneyPath(path)),
      admitted(said, UnderJourneyPath(path), startsTurn: false),
      admitted(said, StartsJourneyPath(InJourney(journey))),
      admitted(said, const StartsJourneyPath(StartsJourney())),
    ];
    for (final decision in decisions) {
      final entry = _entry(decision);
      final full = decodeDecision(
        DecisionEntryKind.admitted,
        encodeDecision(decision).$2,
      )!;
      final narrow = _read(entry);
      switch ((full as EventAdmitted).placement) {
        case StartsJourneyPath(journey: final placement):
          final starts = narrow as StartsPath<JsonObject>;
          expect(starts.event, full.event);
          expect(starts.by, full.by);
          expect(starts.path, JourneyPathId.of(entry));
          expect(starts.journey, switch (placement) {
            InJourney(:final journey) => journey,
            StartsJourney() => JourneyId.of(entry),
          });
          expect(starts.rules.asUncheckedMap(), full.rules!.asUncheckedMap());
        case _:
          expect(narrow, isA<StartsNoPath<JsonObject>>(), reason: '$full');
      }
    }
  });

  test('a path is named by the whole entry, header included', () {
    final decision = EventAdmitted(
      event,
      by: DecidedBy.rules,
      reading: said,
      placement: const StartsJourneyPath(StartsJourney()),
      rules: rules,
      startsTurn: true,
    );
    final a = _read(_entry(decision)) as StartsPath;
    final b = _read(_entry(decision, follows: _b)) as StartsPath;
    expect(a.path, isNot(b.path));
  });

  test('anything else is unreadable, never no path', () {
    final good = {
      'event': 'a' * 64,
      'by': 'rules',
      'reading': {'case': 'message-said', 'node': 'never decoded'},
      'startsJourneyPath': true,
      'startsJourney': true,
      'rules': {'tools': 'all'},
      'startsTurn': true,
    };
    expect(_read(_raw('admitted', good)), isA<StartsPath<JsonObject>>());
    final under = {...good, 'journeyPath': _c}
      ..remove('startsJourneyPath')
      ..remove('startsJourney')
      ..remove('rules');
    expect(_read(_raw('admitted', under)), isA<StartsNoPath<JsonObject>>());

    final bad = <Uint8List>[
      Uint8List.fromList(utf8.encode('admitted')),
      _raw('declined', good),
      _raw('admitted', {...good, 'extra': 1}),
      _raw('admitted', {...good, 'event': 'x'}),
      _raw('admitted', {...good, 'by': 'nobody'}),
      _raw('admitted', {...good, 'reading': 'message-said'}),
      _raw('admitted', {...good, 'reading': <String, Object?>{}}),
      _raw('admitted', {...good}..remove('rules')),
      _raw('admitted', {...good, 'rules': 'all'}),
      _raw('admitted', {
        ...under,
        'rules': {'tools': 'all'},
      }),
      _raw('admitted', {...good}..remove('startsTurn')),
      _raw('admitted', {...good, 'startsTurn': 'yes'}),
      _raw('admitted', {...good, 'startsTurn': false}),
      _raw('admitted', {
        ...good,
        'reading': {'case': 'conversation-joined'},
      }),
      _raw('admitted', {...good, 'journey': _b}),
      _raw('admitted', {...good, 'startsJourneyPath': 1}),
      _raw('admitted', {...under, 'journeyPath': 'x'}),
      Uint8List.fromList([...utf8.encode('admitted\n-\n'), 0xff]),
    ];
    for (final entry in bad) {
      expect(
        _read(entry),
        isA<UnreadablePathEntry<JsonObject>>(),
        reason: utf8.decode(entry, allowMalformed: true),
      );
    }
  });
}
