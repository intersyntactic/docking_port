// What the service's config file lets in: which addresses in external systems
// it reads, which it refuses to start with, and what the list then takes in.
import 'dart:convert';

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_shapes/is_shapes.dart' show ActorId;
import 'package:test/test.dart';

const _channel = 'teams:19:channel@thread.tacv2';
const _chat = 'teams:19:chat@thread.v2';
const _noRules = <String, Object?>{};

String _config(Object? addressesLetIn) =>
    jsonEncode({'addressesLetIn': addressesLetIn});

/// Something said at [address], within [within].
MessageSaid _said(String address, {String? within}) => MessageSaid(
  conversation: ConversationId.parse(address)!,
  within: within == null ? null : ConversationId.parse(within)!,
  key: EventKey.parse('message:1')!,
  node: UserSaid(
    author: ActorId.parse('teams:t/p')!,
    source: SourceMessageId.parse('$address|1')!,
    text: 'hello',
  ),
);

void main() {
  final list = AddressesLetIn.parse(
    _config([
      {
        'addressInExternalSystem': _channel,
        'rules': {'tools': 'channel'},
      },
      {
        'addressInExternalSystem': _chat,
        'rules': {'tools': 'chat'},
      },
    ]),
  );

  group('takes in', () {
    test('a thread of a channel on the list, under the channel\'s rules', () {
      expect(
        list.takeIn(_said('$_channel;messageid=1', within: _channel)),
        const JsonObject.of({'tools': 'channel'}),
      );
    });

    test('a chat on the list, under its own rules', () {
      expect(list.takeIn(_said(_chat)), const JsonObject.of({'tools': 'chat'}));
    });

    test('nothing off the list: another chat, or a thread of another '
        'channel', () {
      expect(list.takeIn(_said('teams:19:other@thread.v2')), isNull);
      expect(
        list.takeIn(
          _said(
            'teams:19:other@thread.tacv2;messageid=1',
            within: 'teams:19:other@thread.tacv2',
          ),
        ),
        isNull,
      );
    });

    test('a thread by its own address alone, when its channel is not on '
        'the list', () {
      // Only what the thread sits within is asked about.
      final threadOnly = AddressesLetIn.parse(
        _config([
          {
            'addressInExternalSystem': '$_channel;messageid=1',
            'rules': _noRules,
          },
        ]),
      );
      expect(
        threadOnly.takeIn(_said('$_channel;messageid=1', within: _channel)),
        isNull,
      );
    });
  });

  group('refuses a config with', () {
    void refuses(String text) => expect(
      () => AddressesLetIn.parse(text),
      throwsA(isA<FormatException>()),
    );

    test('a key it does not take, at the top', () {
      refuses(
        jsonEncode({
          'addressesLetIn': [
            {'addressInExternalSystem': _chat, 'rules': _noRules},
          ],
          'extra': true,
        }),
      );
    });

    test('a key it does not take, in an entry', () {
      refuses(
        _config([
          {'addressInExternalSystem': _chat, 'rules': _noRules, 'note': 'x'},
        ]),
      );
    });

    test('an address that is not one', () {
      for (final address in ['19:chat@thread.v2', 'Teams:x', 'teams:', '']) {
        refuses(
          _config([
            {'addressInExternalSystem': address, 'rules': _noRules},
          ]),
        );
      }
    });

    test('an address named twice', () {
      refuses(
        _config([
          {'addressInExternalSystem': _chat, 'rules': _noRules},
          {'addressInExternalSystem': _chat, 'rules': _noRules},
        ]),
      );
    });

    test('rules that are not an object, or none', () {
      refuses(
        _config([
          {'addressInExternalSystem': _chat, 'rules': 'all'},
        ]),
      );
      refuses(
        _config([
          {'addressInExternalSystem': _chat},
        ]),
      );
    });

    test('no address at all', () {
      refuses(_config([]));
      refuses(jsonEncode(_noRules));
    });

    test('something that is not a JSON object', () {
      refuses('[]');
      refuses('not json');
    });
  });

  test('every message said starts a turn', () {
    expect(
      const EverySaidStartsATurn().startsTurn(
        _said(_chat),
        const StartsJourneyPath(StartsJourney()),
      ),
      isTrue,
    );
  });
}
