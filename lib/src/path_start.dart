/// Reading an `admitted` entry for the journey path it starts and that
/// path's rules, and nothing else: for the airlock, which enforces each
/// path's rules and learns them from the record (RULINGS, "the loop
/// launcher records itself").
///
/// The entry's `reading` is what strangers sent, made into a node. The
/// airlock has no need of it, so it is checked to be an object naming its
/// case and is never decoded: nothing here imports the packages that
/// decode it, and a test holds that. Every other field is read as
/// strictly as `decodeDecision` reads it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart'
    show DecidedBy, JourneyId, JourneyPathId;

/// What an `admitted` entry says about the journey paths it starts:
/// [StartsPath], [StartsNoPath], or [UnreadablePathEntry]. A reader that
/// enforces rules must stop on the last: a path it skipped is one whose
/// rules it never learnt.
sealed class AdmittedPathEntry<R> {
  const AdmittedPathEntry();
}

/// The entry starts [path], in [journey], under [rules].
final class StartsPath<R> extends AdmittedPathEntry<R> {
  const StartsPath({
    required this.event,
    required this.by,
    required this.path,
    required this.journey,
    required this.rules,
  });

  /// The event admitted, by its entry's hash.
  final EntryHash event;
  final DecidedBy by;
  final JourneyPathId path;
  final JourneyId journey;
  final R rules;
}

/// The entry is read, and starts no journey path: it goes under one
/// already started, or is a join.
final class StartsNoPath<R> extends AdmittedPathEntry<R> {
  const StartsNoPath();
}

/// The entry is not one `encodeDecision` writes as `admitted`, for the
/// reason [why].
final class UnreadablePathEntry<R> extends AdmittedPathEntry<R> {
  const UnreadablePathEntry(this.why);

  final String why;

  @override
  String toString() => 'UnreadablePathEntry: $why';
}

/// The record entry [entry] (its bytes as the record holds them, the
/// `<kind>\n<previous>\n` header included, which its ids are hashes of),
/// read for the journey path it starts. [rules] reads the rules from their
/// JSON, null when they aren't rules.
AdmittedPathEntry<R> readPathStart<R>(
  Uint8List entry, {
  required R? Function(Object? json) rules,
}) {
  UnreadablePathEntry<R> unreadable(String why) => UnreadablePathEntry(why);

  final first = entry.indexOf(0x0a);
  final second = first < 0 ? -1 : entry.indexOf(0x0a, first + 1);
  if (second < 0) return unreadable('no `<kind>\\n<previous>\\n` header');
  final kind = ascii.decode(
    Uint8List.sublistView(entry, 0, first),
    allowInvalid: true,
  );
  if (kind != 'admitted') return unreadable('kind `$kind`, not `admitted`');

  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(Uint8List.sublistView(entry, second + 1)));
  } on FormatException catch (e) {
    return unreadable('not JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) return unreadable('not an object');
  final json = decoded;
  final fields = {'event', 'by', 'reading'};

  final event = switch (json['event']) {
    final String hex => EntryHash.parse(hex),
    _ => null,
  };
  if (event == null) return unreadable('`event` is not an entry hash');
  final by = switch (json['by']) {
    final String name => DecidedBy.values.asNameMap()[name],
    _ => null,
  };
  if (by == null) return unreadable('`by` is not who decided');
  final readingCase = switch (json['reading']) {
    {'case': final String readingCase} => readingCase,
    _ => null,
  };
  if (readingCase == null) return unreadable('`reading` names no case');

  // Where it goes: under a path, or into a journey, starting a path or not.
  JourneyPathId? underPath;
  JourneyId? inJourney;
  var startsJourney = false;
  var startsPath = false;
  if (json.containsKey('journeyPath')) {
    underPath = switch (json['journeyPath']) {
      final String hex => JourneyPathId.parse(hex),
      _ => null,
    };
    if (underPath == null) return unreadable('`journeyPath` is not an id');
    fields.add('journeyPath');
  } else {
    if (json.containsKey('journey') == json.containsKey('startsJourney')) {
      return unreadable('not exactly one of `journey` and `startsJourney`');
    }
    if (json.containsKey('journey')) {
      inJourney = switch (json['journey']) {
        final String hex => JourneyId.parse(hex),
        _ => null,
      };
      if (inJourney == null) return unreadable('`journey` is not an id');
      fields.add('journey');
    } else {
      if (json['startsJourney'] != true) {
        return unreadable('`startsJourney` is not true');
      }
      startsJourney = true;
      fields.add('startsJourney');
    }
    if (json.containsKey('startsJourneyPath')) {
      if (json['startsJourneyPath'] != true) {
        return unreadable('`startsJourneyPath` is not true');
      }
      startsPath = true;
      fields.add('startsJourneyPath');
    }
  }

  // Rules exactly when it starts a journey or a path, as EventAdmitted.
  final R? read;
  if (json.containsKey('rules')) {
    read = rules(json['rules']);
    if (read == null) return unreadable('`rules` are not rules');
    fields.add('rules');
  } else {
    read = null;
  }
  if ((read != null) != (startsPath || startsJourney)) {
    return unreadable('`rules` not given exactly when something starts');
  }

  // Whether it starts a turn, exactly for something said, and never
  // false on a path's start.
  final said = readingCase == 'message-said';
  if (json.containsKey('startsTurn') != said) {
    return unreadable('`startsTurn` not given exactly for something said');
  }
  if (said) {
    final startsTurn = json['startsTurn'];
    if (startsTurn is! bool) return unreadable('`startsTurn` is not a bool');
    if (startsPath && !startsTurn) {
      return unreadable('a path started by something that starts no turn');
    }
    fields.add('startsTurn');
  }

  if (json.length != fields.length) {
    return unreadable(
      'fields beyond ${fields.join(', ')}: '
      '${json.keys.where((k) => !fields.contains(k)).join(', ')}',
    );
  }
  if (!startsPath) return StartsNoPath();
  return StartsPath(
    event: event,
    by: by,
    path: JourneyPathId.of(entry),
    journey: inJourney ?? JourneyId.of(entry),
    rules: read as R,
  );
}
