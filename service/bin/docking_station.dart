/// The docking station as a service: it reads the record through the
/// logbook's read socket, decides each event, and sends each decision
/// through the logbook's write socket (RULINGS, "The docking station admits
/// events under journey paths").
///
///   dart run bin/docking_station.dart
///     --read-socket=/run/record-read/logbook.sock   the logbook's read socket
///     --write-socket=/run/record/logbook.sock       the logbook's write socket
///     --config=/etc/.../config.json        the addresses let in, as
///                                          [AddressesLetIn] reads them
///     --what-may-leave-this-machine=/etc/.../hart.json
///                                          the bot's rules file, read as
///                                          [WhatMayLeaveThisMachine]
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
import 'package:is_logbook_client/is_logbook_client.dart';
import 'package:is_teams_module/is_teams_module.dart' show TeamsReading;

const _options = {
  'read-socket',
  'write-socket',
  'config',
  'what-may-leave-this-machine',
  'start-kind',
};

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
  final whatMayLeaveThisMachine = await _read(
    given['what-may-leave-this-machine']!,
    'the rules file',
    readWhatMayLeaveThisMachine,
  );
  final addressesLetIn = await _read(
    given['config']!,
    'the config',
    (text) => AddressesLetIn.parse(
      text,
      whatMayLeaveThisMachine: whatMayLeaveThisMachine,
    ),
  );

  final reader = LogbookReader(given['read-socket']!);
  final writer = LogbookWriter(given['write-socket']!);
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
    missions: addressesLetIn,
    turns: const EverySaidStartsATurn(),
  );
  _abort('stopped: the record\'s subscription ended', 1);
}

/// [path]'s contents as [read] reads them, or exit 78 naming [what].
Future<T> _read<T>(String path, String what, T Function(String) read) async {
  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException catch (e) {
    _abort('$what could not be read: ${e.message}', 78);
  }
  try {
    return read(text);
  } on FormatException catch (e) {
    _abort('$what is not one this reads: ${e.message}', 78);
  }
}

Never _abort(String why, int code) {
  stderr.writeln('abort: $why');
  exit(code);
}
