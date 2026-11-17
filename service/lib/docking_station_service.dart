/// The rules the docking station runs under as a service, for now: a list of
/// the addresses in external systems let in, what may leave this machine for
/// every mission they start, and every message said starting a turn.
///
/// The list and the turn rule stand in for calls still open (Nick, 15 Nov:
/// for Wednesday a new chat or channel comes in by a rule, not by his yes),
/// so they stay here, beside the program, and not in the library. What may
/// leave this machine is the bot's own file (Nick, 17 Nov: one file per bot).
library;

import 'dart:convert';

import 'package:checked_json/checked_json.dart'
    show JsonFieldException, JsonObject;
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_flight_rules/is_flight_rules.dart';

/// The addresses in external systems whose missions come in, each under
/// [whatMayLeaveThisMachine], the bot's rules. A channel on the list lets in
/// each of its threads, as the mission they sit in; a chat on the list lets
/// itself in. Anything else is not taken in.
///
/// The list is read from the service's config file, a JSON object:
///
///     {"addressesLetIn": ["teams:19:abc@thread.tacv2", ...]}
///
/// Read strictly: an unknown key, an address that isn't one, an address
/// named twice, or an empty list refuses the whole file, since a service
/// that started with half a list would turn away missions nobody meant to.
final class AddressesLetIn implements JourneyRule {
  AddressesLetIn._(this.addresses, this.whatMayLeaveThisMachine)
    : _rules = whatMayLeaveThisMachine.toJson();

  /// The list in [config], the config file's contents, under
  /// [whatMayLeaveThisMachine]. Throws a [FormatException] naming what is
  /// wrong.
  factory AddressesLetIn.parse(
    String config, {
    required WhatMayLeaveThisMachine whatMayLeaveThisMachine,
  }) {
    final json = _object(config, 'the config');
    _onlyKeys(json, const {'addressesLetIn'}, 'the config');
    final addresses = <AddressInExternalSystem>{};
    for (final text in json.strings('addressesLetIn')) {
      final address =
          AddressInExternalSystem.parse(text) ??
          (throw JsonFieldException(
            'addressesLetIn',
            'addresses: a system, a colon and its id, such as '
                'teams:19:abc@thread.v2',
          ));
      if (!addresses.add(address)) {
        throw FormatException('$address is named twice');
      }
    }
    if (addresses.isEmpty) {
      throw const FormatException('addressesLetIn names no address');
    }
    return AddressesLetIn._(
      Set.unmodifiable(addresses),
      whatMayLeaveThisMachine,
    );
  }

  /// The addresses on the list.
  final Set<AddressInExternalSystem> addresses;

  /// What may leave this machine for every mission the list takes in.
  final WhatMayLeaveThisMachine whatMayLeaveThisMachine;

  final JsonObject _rules;

  @override
  JsonObject? takeIn(AdmissibleEvent first) =>
      addresses.contains(
        first.containingAddress ?? first.addressInExternalSystem,
      )
      ? _rules
      : null;
}

/// The bot's rules file, [text], read strictly: an unknown key at any level
/// throws a [FormatException] naming the part, so a typo stops the service
/// before any mission starts under it.
WhatMayLeaveThisMachine readWhatMayLeaveThisMachine(String text) =>
    WhatMayLeaveThisMachine.fromJson(_object(text, 'the rules file'));

/// Every message said starts a turn: Teams is taken to deliver only what
/// @mentions the agent, so each one is asked of it. Whether Teams does is
/// still to be confirmed in a real channel.
final class EverySaidStartsATurn implements TurnRule {
  const EverySaidStartsATurn();

  @override
  bool startsTurn(MessageSaid said, AdmittedPlacement placement) => true;
}

JsonObject _object(String text, String what) =>
    JsonObject.parse(jsonDecode(text)) ??
    (throw FormatException('$what is not a JSON object'));

void _onlyKeys(JsonObject json, Set<String> allowed, String what) {
  for (final key in json.asUncheckedMap().keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$what has a key it does not take: $key');
    }
  }
}
