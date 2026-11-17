// What the service's config file lets in, and the bot's rules file every
// mission it lets in starts under: which files it reads, which it refuses to
// start with, and what the list then takes in.
import 'dart:convert';

import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_shapes/is_shapes.dart' show ActorId;
import 'package:test/test.dart';

const _channel = 'teams:19:channel@thread.tacv2';
const _chat = 'teams:19:chat@thread.v2';

/// A rules file as Hart's bot might have it.
const _rulesFile = {
  'modelSignInsCallsMayGoOutAs': ['claude-team'],
  'sitesTheWebDriverMayReach': [
    {
      'site': 'https://docs.example.com',
      'goesAs': {'kind': 'nobody'},
    },
  ],
  'programsNetwork': 'noNetworkOfTheirOwn',
};

final _rules = readWhatMayLeaveThisMachine(jsonEncode(_rulesFile));

String _config(Object? addressesLetIn) =>
    jsonEncode({'addressesLetIn': addressesLetIn});

AddressesLetIn _parse(String config) =>
    AddressesLetIn.parse(config, whatMayLeaveThisMachine: _rules);

/// Something said at [address], in [containing].
MessageSaid _said(String address, {String? containing}) => MessageSaid(
  addressInExternalSystem: AddressInExternalSystem.parse(address)!,
  containingAddress: containing == null
      ? null
      : AddressInExternalSystem.parse(containing)!,
  key: EventKey.parse('message:1')!,
  node: UserSaid(
    author: ActorId.parse('teams:t/p')!,
    source: SourceMessageId.parse('$address|1')!,
    text: 'hello',
  ),
);

void main() {
  final list = _parse(_config([_channel, _chat]));

  group('takes in, under the bot\'s rules', () {
    test('a thread of a channel on the list', () {
      expect(
        list.takeIn(_said('$_channel;messageid=1', containing: _channel)),
        _rules.toJson(),
      );
    });

    test('a chat on the list', () {
      expect(list.takeIn(_said(_chat)), _rules.toJson());
    });

    test('the rules as written in the file, read back unchanged', () {
      expect(jsonDecode(jsonEncode(list.takeIn(_said(_chat)))), _rulesFile);
    });

    test('nothing off the list: another chat, or a thread of another '
        'channel', () {
      expect(list.takeIn(_said('teams:19:other@thread.v2')), isNull);
      expect(
        list.takeIn(
          _said(
            'teams:19:other@thread.tacv2;messageid=1',
            containing: 'teams:19:other@thread.tacv2',
          ),
        ),
        isNull,
      );
    });

    test('a thread by its own address alone, when its channel is not on '
        'the list', () {
      // Only the address a thread sits in is asked about.
      final threadOnly = _parse(_config(['$_channel;messageid=1']));
      expect(
        threadOnly.takeIn(_said('$_channel;messageid=1', containing: _channel)),
        isNull,
      );
    });
  });

  group('refuses a config with', () {
    void refuses(String text) =>
        expect(() => _parse(text), throwsA(isA<FormatException>()));

    test('a key it does not take', () {
      refuses(
        jsonEncode({
          'addressesLetIn': [_chat],
          'extra': true,
        }),
      );
    });

    test('an address that is not one', () {
      for (final address in ['19:chat@thread.v2', 'Teams:x', 'teams:', '']) {
        refuses(_config([address]));
      }
      refuses(
        _config([
          {'addressInExternalSystem': _chat},
        ]),
      );
    });

    test('an address named twice', () {
      refuses(_config([_chat, _chat]));
    });

    test('no address at all', () {
      refuses(_config([]));
      refuses(jsonEncode(<String, Object?>{}));
    });

    test('something that is not a JSON object', () {
      refuses('[]');
      refuses('not json');
    });
  });

  group('refuses a rules file with', () {
    void refuses(Object? json) => expect(
      () => readWhatMayLeaveThisMachine(jsonEncode(json)),
      throwsA(isA<FormatException>()),
    );

    test('a key it does not know, at the top or inside', () {
      refuses({..._rulesFile, 'note': 'x'});
      refuses({
        ..._rulesFile,
        'sitesTheWebDriverMayReach': [
          {
            'site': 'https://docs.example.com',
            'goesAs': {'kind': 'nobody', 'why': 'x'},
          },
        ],
      });
    });

    test('a part missing', () {
      refuses({..._rulesFile}..remove('programsNetwork'));
    });

    test('something that is not a JSON object', () {
      refuses([_rulesFile]);
    });
  });

  test('every message said starts a turn', () {
    expect(
      const EverySaidStartsATurn().startsTurn(
        _said(_chat),
        const StartsTrajectory(StartsMission()),
      ),
      isTrue,
    );
  });
}
