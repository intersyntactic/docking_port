/// The rules the docking station runs under as a service, for now: a list of
/// the addresses in external systems let in, each with the rules its journey
/// is taken in under, and every message said starting a turn.
///
/// Both stand in for calls still open (Nick, 15 Nov: for Wednesday a new
/// chat or channel comes in by a rule, not by his yes), so they stay here,
/// beside the program, and not in the library.
library;

import 'dart:convert';

import 'package:checked_json/checked_json.dart'
    show JsonFieldException, JsonObject;
import 'package:is_docking_station/is_docking_station.dart';

/// The addresses in external systems whose journeys come in, each with the
/// rules its journey is taken in under. A channel on the list lets in each
/// of its threads, as the journey they sit within; a chat on the list lets
/// itself in. Anything else is not taken in.
///
/// Read from the service's config file, a JSON object:
///
///     {"addressesLetIn": [
///       {"addressInExternalSystem": "teams:19:abc@thread.tacv2",
///        "rules": {...}}
///     ]}
///
/// Read strictly: an unknown key, an address that isn't one, an address
/// named twice, rules that aren't an object, or an empty list refuse the
/// whole file, since a service that started with half a list would turn
/// away journeys nobody meant to.
final class AddressesLetIn implements JourneyRule {
  AddressesLetIn._(this._rules);

  final Map<ConversationId, JsonObject> _rules;

  /// The list in [text], the config file's contents. Throws a
  /// [FormatException] naming what is wrong.
  factory AddressesLetIn.parse(String text) {
    final json = JsonObject.parse(jsonDecode(text));
    if (json == null) {
      throw const FormatException('the config is not a JSON object');
    }
    _onlyKeys(json, const {'addressesLetIn'}, 'the config');
    final rules = <ConversationId, JsonObject>{};
    for (final entry in json.objects('addressesLetIn')) {
      _onlyKeys(entry, const {'addressInExternalSystem', 'rules'}, 'an entry');
      final text = entry.string('addressInExternalSystem');
      final address =
          ConversationId.parse(text) ??
          (throw JsonFieldException(
            'addressInExternalSystem',
            'a system, a colon and its id, such as teams:19:abc@thread.v2',
          ));
      if (rules.containsKey(address)) {
        throw FormatException('$address is named twice');
      }
      rules[address] = entry.object('rules').deepFrozen();
    }
    if (rules.isEmpty) {
      throw const FormatException('addressesLetIn names no address');
    }
    return AddressesLetIn._(Map.unmodifiable(rules));
  }

  /// The addresses on the list.
  Iterable<ConversationId> get addresses => _rules.keys;

  @override
  JsonObject? takeIn(AdmissibleEvent first) =>
      _rules[first.within ?? first.conversation];
}

/// Every message said starts a turn: Teams is taken to deliver only what
/// @mentions the agent, so each one is asked of it. Whether Teams does is
/// still to be confirmed in a real channel.
final class EverySaidStartsATurn implements TurnRule {
  const EverySaidStartsATurn();

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) => true;
}

void _onlyKeys(JsonObject json, Set<String> allowed, String what) {
  for (final key in json.asUncheckedMap().keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$what has a key it does not take: $key');
    }
  }
}
