/// The docking station as a service: it reads the record through the
/// journal's read socket, decides each event, and sends each decision
/// through the journal's write socket (RULINGS, "The docking station admits
/// events under journey paths").
///
///   dart run bin/docking_station.dart
///     --read-socket=/run/.../read.sock     the journal's read socket
///     --write-socket=/run/.../write.sock   the journal's write socket
///     --config=/etc/.../config.json        the addresses let in, as
///                                          [AddressesLetIn] reads them
///     --start-kind=KIND                    the kind of the start entry,
///                                          written once at setup
///
/// It exits non-zero whenever the docking station stops, whether it returns
/// or throws: it should run for as long as the record does, so the service
/// manager starts it again, and it reads back whatever got in.
library;

import 'dart:io';

import 'package:docking_station_service/docking_station_service.dart';
import 'package:is_docking_station/is_docking_station.dart';
import 'package:is_journal_client/is_journal_client.dart';
import 'package:is_teams_module/is_teams_module.dart' show TeamsReading;

const _options = {'read-socket', 'write-socket', 'config', 'start-kind'};

Future<void> main(List<String> arguments) async {
  final given = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(r'^--([a-z-]+)=(.+)$').firstMatch(argument);
    final name = match?.group(1);
    if (match == null || !_options.contains(name)) {
      _abort('unknown argument: $argument', 64);
    }
    if (given.containsKey(name)) _abort('--$name given twice', 64);
    given[name!] = match.group(2)!;
  }
  for (final name in _options) {
    if (!given.containsKey(name)) _abort('--$name is required', 64);
  }

  final startKind =
      Kind.parse(given['start-kind']!) ??
      _abort('--start-kind "${given['start-kind']}" is not a kind', 64);
  final AddressesLetIn addressesLetIn;
  try {
    addressesLetIn = AddressesLetIn.parse(
      await File(given['config']!).readAsString(),
    );
  } on FileSystemException catch (e) {
    _abort('the config could not be read: ${e.message}', 78);
  } on FormatException catch (e) {
    _abort('the config is not one this reads: ${e.message}', 78);
  }

  final reader = JournalReader(given['read-socket']!);
  final writer = JournalWriter(given['write-socket']!);
  stderr.writeln(
    'docking station: ${addressesLetIn.addresses.length} addresses let in, '
    'start entry of kind $startKind',
  );
  // What it throws is left uncaught: the program exits 255 with it printed,
  // a [StateError] for a decision refused or unanswered, a [ReadFailure]
  // for the read socket gone.
  await runDockingStation(
    subscribe: (kinds) => reader.subscribe(kinds: kinds),
    send: writer.write,
    startKind: startKind,
    readings: const [TeamsReading()],
    journeys: addressesLetIn,
    turns: const EverySaidStartsATurn(),
  );
  _abort('stopped: the record\'s subscription ended', 1);
}

Never _abort(String why, int code) {
  stderr.writeln('abort: $why');
  exit(code);
}
