// What [decide] makes of events against what [DecidedSoFar] holds, without a
// record: the questions one decision asks of the ones before it.
import 'dart:convert';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show ActorId, DecidedBy, JourneyId;
import 'package:test/test.dart';

final class _All implements JourneyRule, TurnRule {
  @override
  JsonObject takeIn(AdmissibleEvent first) =>
      const JsonObject.of({'tools': 'all'});

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) => true;
}

EntryHash _hash(String s) => EntryHash.of(utf8.encode(s));

void main() {
  test('every duplicate names the first event with its key, not the copy '
      'before it', () {
    final said = MessageSaid(
      conversation: ConversationId.parse('test:chat')!,
      within: null,
      key: EventKey.parse('message:1')!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('chat|1')!,
        text: 'hello',
      ),
    );
    final decided = DecidedSoFar();
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
      if (decision case DuplicateEvent(:final of)) ofs.add(of);
      decided.take(_hash('decision $i'), decision);
    }
    // A third copy is where naming the copy before shows: two copies name
    // the first either way.
    expect(ofs, [events[0], events[0], events[0]]);
  });

  test('a path started in a journey already taken in records the rules '
      'the journey was taken in under, without asking the rule again', () {
    final channel = ConversationId.parse('test:channel')!;
    MessageSaid said(String thread, String key) => MessageSaid(
      conversation: ConversationId.parse('test:channel;$thread')!,
      within: channel,
      key: EventKey.parse(key)!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('$thread|$key')!,
        text: 'hi',
      ),
    );
    final rule = _Counting();
    final decided = DecidedSoFar();
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
    expect((first as EventAdmitted).placement, isA<StartsJourneyPath>());
    final placement = (second as EventAdmitted).placement;
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

  test('after a journey ends, its conversation starts a new path in the '
      'same journey, under the same rules', () {
    final channel = ConversationId.parse('test:channel')!;
    MessageSaid said(String key) => MessageSaid(
      conversation: ConversationId.parse('test:channel;t1')!,
      within: channel,
      key: EventKey.parse(key)!,
      node: UserSaid(
        author: ActorId.parse('teams:t/p')!,
        source: SourceMessageId.parse('t1|$key')!,
        text: 'hi',
      ),
    );
    final rule = _Counting();
    final decided = DecidedSoFar();
    AdmissionDecision step(String key) {
      final decision = decide(
        _hash(key),
        said(key),
        decided,
        journeys: rule,
        turns: _All(),
      );
      decided.take(_hash('decision $key'), decision);
      return decision;
    }

    final first = step('a') as EventAdmitted;
    final journey = JourneyId.parse(_hash('decision a').hex)!;
    expect(
      step('b'),
      isA<EventAdmitted>().having(
        (a) => a.placement,
        'placement',
        isA<UnderJourneyPath>(),
      ),
    );
    decided.take(
      _hash('end'),
      JourneyEnded(
        _hash('asked to end'),
        by: DecidedBy.person,
        journey: journey,
      ),
    );
    final again = step('c') as EventAdmitted;
    expect(
      again.placement,
      isA<StartsJourneyPath>().having(
        (p) => p.journey,
        'journey',
        isA<InJourney>().having((j) => j.journey, 'journey', journey),
      ),
    );
    expect(again.rules?.asUncheckedMap(), first.rules?.asUncheckedMap());
    expect(rule.asked, 1);
  });
}

/// Takes every journey in, under rules that say how many times it was
/// asked.
final class _Counting implements JourneyRule {
  var asked = 0;

  @override
  JsonObject takeIn(AdmissibleEvent first) => JsonObject.of({'asked': ++asked});
}
