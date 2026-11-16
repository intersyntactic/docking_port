// What [decide] makes of events against what [Decided] holds, without a
// record: the questions one decision asks of the ones before it.
import 'dart:convert';

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show ActorId;
import 'package:test/test.dart';

final class _All implements JourneyRule, TurnRule {
  @override
  bool takesIn(Admissible first) => true;

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
}
