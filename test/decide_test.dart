// What [decide] makes of events against what [Decided] holds, without a
// record: the questions one decision asks of the ones before it.
import 'dart:convert';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show ActorId, JourneyId;
import 'package:test/test.dart';

final class _All implements JourneyRule, TurnRule {
  @override
  JsonObject takeIn(Admissible first) => const JsonObject.of({'tools': 'all'});

  @override
  bool startsTurn(Said said, Placement placement) => true;
}

EntryHash _hash(String s) => EntryHash.of(utf8.encode(s));

void main() {
  test('every duplicate names the first event with its key, not the copy '
      'before it', () {
    final said = Said(
      conversation: Conversation.parse('test:chat')!,
      within: null,
      key: EventKey.parse('message:1')!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('chat|1')!,
        text: 'hello',
      ),
    );
    final decided = Decided();
    final events = [for (final name in 'ABCD'.split('')) _hash(name)];
    final ofs = <EntryHash>[];
    for (final (i, event) in events.indexed) {
      final decision = decide(
        event,
        said,
        decided,
        journeys: _All(),
        turns: _All(),
      );
      if (decision case Duplicate(:final of)) ofs.add(of);
      decided.take(_hash('decision $i'), decision);
    }
    // A third copy is where naming the copy before shows: two copies name
    // the first either way.
    expect(ofs, [events[0], events[0], events[0]]);
  });

  test('a path started in a journey already taken in records the rules '
      'the journey was taken in under, without asking the rule again', () {
    final channel = Conversation.parse('test:channel')!;
    Said said(String thread, String key) => Said(
      conversation: Conversation.parse('test:channel;$thread')!,
      within: channel,
      key: EventKey.parse(key)!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('$thread|$key')!,
        text: 'hi',
      ),
    );
    final rule = _Counting();
    final decided = Decided();
    final first = decide(
      _hash('A'),
      said('t1', 'a'),
      decided,
      journeys: rule,
      turns: _All(),
    );
    decided.take(_hash('decision A'), first);
    final second = decide(
      _hash('B'),
      said('t2', 'b'),
      decided,
      journeys: rule,
      turns: _All(),
    );
    expect(rule.asked, 1);
    expect((first as Admitted).placement, isA<StartsJourneyPath>());
    final placement = (second as Admitted).placement;
    expect(
      placement,
      isA<StartsJourneyPath>().having(
        (p) => p.journey,
        'journey',
        isA<InJourney>().having(
          (j) => j.journey,
          'journey',
          JourneyId.parse(_hash('decision A').hex),
        ),
      ),
    );
    expect(second.rules?.asUncheckedMap(), {'asked': 1});
  });
}

/// Takes every journey in, under rules that say how many times it was
/// asked.
final class _Counting implements JourneyRule {
  var asked = 0;

  @override
  JsonObject takeIn(Admissible first) => JsonObject.of({'asked': ++asked});
}
