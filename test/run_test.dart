// What the docking station sends a record, and when: against a record kept in
// memory the way the journal service keeps one.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_loop/agent_loop.dart'
    show CaughtUp, FollowItem, JournalEntryFrame, JournalWriteRefused;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart' show ActorId, DecidedBy;
import 'package:test/test.dart';

final ann = ActorId.parse('teams:t/p')!;
final chat = Conversation.parse('test:chat')!;

/// A record in memory: entries in order, a follow that sends the backlog,
/// then caught-up, then each new entry, and one chain of decisions whose
/// tip a sent decision must follow, as the journal service checks.
final class _Record {
  final _entries = <JournalEntryFrame>[];
  final _followers = <(Set<Kind>, StreamController<FollowItem>)>[];
  EntryHash? _tip;

  /// Each decision sent, refused or not, with what it followed.
  final sent = <(EntryHash?, Decision)>[];

  /// Run once, as the next decision is sent, before it is checked.
  void Function()? beforeNextSend;

  /// Why every decision sent is refused, when set.
  String? refuse;

  /// The decisions recorded, in order.
  List<Decision> get decisions => [
    for (final frame in _entries) ?decodeDecision(frame.kind, frame.body),
  ];

  /// The hashes of the decisions recorded, in order.
  List<EntryHash> get decisionEntries => [
    for (final frame in _entries)
      if (decodeDecision(frame.kind, frame.body) != null) frame.hash,
  ];

  JournalEntryFrame add(String kind, EntryHash? follows, List<int> body) {
    final header = utf8.encode('$kind\n${follows?.hex ?? '-'}\n');
    final bytes = Uint8List.fromList([...header, ...body]);
    // A kind made from its name, never one of the docking station's own, so
    // the docking station has to compare kinds by value.
    final frame = JournalEntryFrame(
      hash: EntryHash.of(bytes),
      kind: Kind.parse(kind)!,
      follows: follows,
      bytes: bytes,
    );
    _entries.add(frame);
    for (final (kinds, follower) in _followers) {
      if (kinds.contains(frame.kind)) follower.add(frame);
    }
    return frame;
  }

  /// An event from [source], whose bytes are [what] as JSON, recorded as an
  /// entry of [kind].
  JournalEntryFrame recordEvent(
    Map<String, Object?> what, {
    String source = 'test',
    String kind = 'event',
  }) => add(
    kind,
    null,
    utf8.encode(
      jsonEncode({
        'at': '2026-11-16T00:00:00Z',
        'source': source,
        'bytes': base64Encode(utf8.encode(jsonEncode(what))),
      }),
    ),
  );

  /// [decision], sent by another docking station, following the tip.
  void decideElsewhere(Decision decision) {
    final (kind, body) = encodeDecision(decision);
    _tip = add(kind.name, _tip, body).hash;
  }

  Stream<FollowItem> follow(Set<Kind> kinds) {
    final follower = StreamController<FollowItem>();
    for (final frame in _entries) {
      if (kinds.contains(frame.kind)) follower.add(frame);
    }
    follower.add(CaughtUp(_entries.lastOrNull?.hash));
    _followers.add((kinds, follower));
    return follower.stream;
  }

  Future<EntryHash> send(Kind kind, EntryHash? follows, Uint8List body) async {
    sent.add((follows, decodeDecision(kind, body)!));
    final before = beforeNextSend;
    beforeNextSend = null;
    before?.call();
    if (refuse case final why?) throw JournalWriteRefused(why);
    if (follows != _tip) throw JournalWriteRefused('$follows is not the tip');
    final hash = add(kind.name, follows, body).hash;
    _tip = hash;
    return hash;
  }

  Future<EntryHash> tipOf(EntryHash entry) async => _tip!;

  Future<void> close() async {
    for (final (_, follower) in _followers) {
      await follower.close();
    }
  }
}

/// Reads an event's bytes, `{"said": <text>, "key": <key>}`, as [ann]
/// saying it in [chat]; anything else as nothing to admit. Keeps which
/// events it was given, in order.
final class _Reading implements ModuleReading<int> {
  final given = <EntryHash>[];

  @override
  String get source => 'test';

  @override
  int get start => 0;

  @override
  (int, Reading) step(int state, Event event) {
    given.add(event.entry);
    final what = jsonDecode(utf8.decode(event.bytes)) as Map<String, Object?>;
    if (what case {'said': final String text, 'key': final String key}) {
      return (
        state + 1,
        Said(
          conversation: chat,
          within: null,
          key: EventKey.parse(key)!,
          node: UserSaid(
            author: ann,
            source: SourceMessageId.parse('chat|$key')!,
            text: text,
          ),
        ),
      );
    }
    return (state + 1, const NothingToAdmit());
  }
}

final class _TakesIn implements JourneyRule {
  const _TakesIn();

  @override
  bool takesIn(Admissible first) => true;
}

final class _EverySaid implements TurnRule {
  const _EverySaid();

  @override
  bool startsTurn(Said said, Placement placement) => true;
}

Future<void> _run(_Record record, _Reading reading) => runDockingStation(
  follow: record.follow,
  send: record.send,
  tipOf: record.tipOf,
  readings: [reading],
  journeys: const _TakesIn(),
  turns: const _EverySaid(),
);

/// Runs the docking station on [record] until it has done all it can, then
/// ends the record and waits for it to finish.
Future<void> _runToEnd(_Record record, _Reading reading) async {
  final running = _run(record, reading);
  await pumpEventQueue();
  await record.close();
  await running;
}

Admitted _startsChat(EntryHash event, String key) => Admitted(
  event,
  by: DecidedBy.rules,
  reading: Said(
    conversation: chat,
    within: null,
    key: EventKey.parse(key)!,
    node: UserSaid(
      author: ann,
      source: SourceMessageId.parse('chat|$key')!,
      text: 'hi',
    ),
  ),
  placement: const StartsJourneyPath(StartsJourney()),
);

void main() {
  test('once caught up, decides each waiting event, each following the '
      'one before', () async {
    final record = _Record();
    final a = record.recordEvent({'said': 'hello', 'key': 'a'});
    final b = record.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(record, _Reading());

    final [(firstFollows, first), (secondFollows, second)] = record.sent;
    final [firstEntry, _] = record.decisionEntries;
    expect(firstFollows, isNull);
    expect(first.event, a.hash);
    expect(first.by, DecidedBy.rules);
    expect(
      (first as Admitted).placement,
      isA<StartsJourneyPath>().having(
        (p) => p.journey,
        'journey',
        isA<StartsJourney>(),
      ),
    );
    expect(secondFollows, firstEntry);
    expect(second.event, b.hash);
    expect(
      ((second as Admitted).placement as Under).journeyPath.hex,
      firstEntry.hex,
    );
  });

  test('takes the decisions in the record, and decides only what is left, '
      'reading every event', () async {
    final record = _Record();
    final reading = _Reading();
    final a = record.recordEvent({'said': 'hello', 'key': 'a'});
    record.decideElsewhere(_startsChat(a.hash, 'a'));
    final b = record.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(record, reading);

    final aDecision = record.decisionEntries.first;
    final [(follows, decision)] = record.sent;
    expect(reading.given, [a.hash, b.hash]);
    expect(follows, aDecision);
    expect(decision.event, b.hash);
    expect(
      ((decision as Admitted).placement as Under).journeyPath.hex,
      aDecision.hex,
    );
  });

  test('decides an event that comes after catching up, as it comes', () async {
    final record = _Record();
    final running = _run(record, _Reading());
    await pumpEventQueue();
    expect(record.sent, isEmpty);

    final c = record.recordEvent({'said': 'late', 'key': 'c'});
    await pumpEventQueue();
    await record.close();
    await running;

    final [(_, decision)] = record.sent;
    expect(decision.event, c.hash);
    expect(record.decisions.map((d) => d.event), [c.hash]);
  });

  test('when another docking station decided first, takes its decision and '
      'sends nothing more', () async {
    final record = _Record();
    final a0 = record.recordEvent({'said': 'hello', 'key': 'a0'});
    record.decideElsewhere(_startsChat(a0.hash, 'a0'));
    final a = record.recordEvent({'said': 'again', 'key': 'a'});
    record.beforeNextSend = () => record.decideElsewhere(
      NotATurn(
        a.hash,
        by: DecidedBy.rules,
        conversation: chat,
        key: EventKey.parse('a')!,
      ),
    );
    await _runToEnd(record, _Reading());

    expect(record.sent, hasLength(1));
    expect(record.decisions.map((d) => d.event), [a0.hash, a.hash]);
    expect(record.decisions.last, isA<NotATurn>());
  });

  test('a refusal while the chain has not moved is rethrown', () async {
    final record = _Record();
    final a0 = record.recordEvent({'said': 'hello', 'key': 'a0'});
    record.decideElsewhere(_startsChat(a0.hash, 'a0'));
    record.recordEvent({'said': 'again', 'key': 'a'});
    record.refuse = 'docking-station may not send admitted';

    await expectLater(
      _run(record, _Reading()),
      throwsA(isA<JournalWriteRefused>()),
    );
    expect(record.decisions, hasLength(1));
    await record.close();
  });

  test('a decision it cannot read stops it', () async {
    final record = _Record();
    record.add('admitted', null, utf8.encode('{"not": "a decision"}'));

    await expectLater(_run(record, _Reading()), throwsA(isA<StateError>()));
    await record.close();
  });

  test('an event from a source no reading takes is declined, unread', () async {
    final record = _Record();
    final x = record.recordEvent({
      'said': 'hi',
      'key': 'x',
    }, source: 'elsewhere');
    final reading = _Reading();
    await _runToEnd(record, reading);

    final [(_, decision)] = record.sent;
    expect(decision, isA<Unread>());
    expect(decision.event, x.hash);
    expect(reading.given, isEmpty);
  });

  test('reads an event recorded before the rename, as `arrived`', () async {
    final record = _Record();
    final reading = _Reading();
    final old = record.recordEvent({
      'said': 'hello',
      'key': 'a',
    }, kind: 'arrived');
    final now = record.recordEvent({'said': 'again', 'key': 'b'});
    await _runToEnd(record, reading);

    expect(reading.given, [old.hash, now.hash]);
    expect(record.decisions.map((d) => d.event), [old.hash, now.hash]);
  });
}
