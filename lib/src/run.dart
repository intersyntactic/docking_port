/// Running the docking station: following the record, deciding each event,
/// and sending each decision to it (RULINGS, "The docking station admits
/// events under journey paths").
library;

import 'dart:typed_data';

import 'package:agent_loop/agent_loop.dart'
    show CaughtUp, FollowItem, JournalEntryFrame, JournalWriteRefused;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;

import 'decide.dart';
import 'decided.dart';
import 'decision.dart';
import 'decision_wire.dart';
import 'reading.dart';
import 'rules.dart';

/// The kinds of entry the record names events by: `event`, and `arrived`,
/// which entries recorded before the rename keep for good, since an entry's
/// kind is part of the bytes its hash is taken from (Nick, 16 Nov: "It's an
/// event, not an arrival").
final _eventKinds = {Kind.parse('event')!, Kind.parse('arrived')!};

/// Runs the docking station until [follow]'s stream ends, which it never
/// should: the caller treats a return as the record going away.
///
/// It follows the record from its start, asking [follow] for its events,
/// its decisions and its start entry, the one entry of [startKind]. Each
/// event is read by the one of [readings] for its source, in the record's
/// order, and each decision is taken into a [DecidedSoFar]. Once [follow]
/// has caught up, each event after the start entry with no decision is
/// decided under [journeys] and [turns], in order, and sent with [send]
/// following the decision before it, or the start entry for the first; so
/// is each event after that, as it comes.
///
/// The start entry is written once, at setup, by whoever sets the docking
/// station up, never by the docking station: two of them starting at once
/// would each write one (Nick, 16 Nov: leave events from before the first
/// run undecided). An event before it is read, so a reading learns from
/// its history, but never decided. With no start entry yet, nothing is
/// decided until one comes. A second start entry, or a decision before
/// the first, stops it: a later start entry that reset what was decided
/// is a call not made (one start entry, intersyntactic-a8 and this
/// session's lean, 16 Nov; the open questions hold it).
///
/// When the record refuses a decision, [tipOf] says whether the decisions'
/// chain has moved on. If it has, another docking station decided first, and
/// its decision comes on the record to be taken like any other. If it
/// hasn't, the refusal is for some other reason, such as a sender table
/// that doesn't allow the kind, and it is rethrown: deciding on regardless
/// could admit an event twice. A decision in the record that can't be read
/// back stops it too, for the same reason.
Future<void> runDockingStation({
  required Stream<FollowItem> Function(Set<Kind> kinds) follow,
  required Future<EntryHash> Function(
    Kind kind,
    EntryHash? follows,
    Uint8List body,
  )
  send,
  required Future<EntryHash> Function(EntryHash entry) tipOf,
  required Kind startKind,
  required Iterable<ModuleReading<Object?>> readings,
  required JourneyRule journeys,
  required TurnRule turns,
}) async {
  final folds = <String, _Fold<Object?>>{};
  for (final reading in readings) {
    if (folds.containsKey(reading.source)) {
      throw ArgumentError.value(
        reading.source,
        'readings',
        'two readings for one source',
      );
    }
    folds[reading.source] = _Fold(reading);
  }
  if (_eventKinds.contains(startKind) ||
      DecisionEntryKind.all.contains(startKind)) {
    throw ArgumentError.value(
      startKind,
      'startKind',
      'is the kind of an event or a decision',
    );
  }
  final decided = DecidedSoFar();
  // The start entry, once it has come.
  EntryHash? start;
  // Each event after the start entry read but not yet decided, with its
  // reading, in the record's order.
  final waiting = <EntryHash, EventReading?>{};

  // Decides each waiting event in order. Returns early when another
  // docking station has decided first: its decisions come on the record.
  Future<void> decideWaiting(EntryHash start) async {
    while (waiting.isNotEmpty) {
      final MapEntry(key: event, value: reading) = waiting.entries.first;
      final decision = decide(
        event,
        reading,
        decided,
        journeys: journeys,
        turns: turns,
      );
      final (kind, body) = encodeDecision(decision);
      final follows = decided.tip ?? start;
      final EntryHash entry;
      try {
        entry = await send(kind, follows, body);
      } on JournalWriteRefused {
        if (await tipOf(follows) != follows) return;
        rethrow;
      }
      decided.take(entry, decision);
      waiting.remove(event);
    }
  }

  var caughtUp = false;
  final kinds = {..._eventKinds, ...DecisionEntryKind.all, startKind};
  await for (final item in follow(kinds)) {
    switch (item) {
      case JournalEntryFrame(:final hash, :final kind)
          when _eventKinds.contains(kind):
        // Read whether or not it is decided, so a reading learns from the
        // events before the start entry too.
        final event = RelayedEvent.read(hash, item.body);
        final reading = switch (event) {
          final event? => folds[event.source]?.step(event),
          null => null,
        };
        if (start != null) waiting[hash] = reading;
      case JournalEntryFrame(:final hash, :final kind) when kind == startKind:
        if (start != null) {
          throw StateError(
            'a second start entry ${hash.hex}, after ${start.hex}',
          );
        }
        start = hash;
      case JournalEntryFrame(:final hash, :final kind):
        if (start == null) {
          throw StateError('the decision ${hash.hex} is before any start');
        }
        final decision =
            decodeDecision(kind, item.body) ??
            (throw StateError('cannot read the decision ${hash.hex}'));
        decided.take(hash, decision);
        waiting.remove(decision.event);
      case CaughtUp():
        caughtUp = true;
    }
    if (caughtUp && start != null) await decideWaiting(start);
  }
}

/// One module's reading, folded: it keeps the state the reading returned
/// last, and gives each event to the reading with it.
final class _Fold<S> {
  _Fold(this._reading) : _state = _reading.start;

  final ModuleReading<S> _reading;
  S _state;

  EventReading step(RelayedEvent event) {
    final (state, reading) = _reading.step(_state, event);
    _state = state;
    return reading;
  }
}
