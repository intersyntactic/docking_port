/// Running the docking port: following the record, deciding each event,
/// and sending each decision to it (RULINGS, "The docking port admits
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

/// The kinds of entry the record names events by: `arrived`, until its
/// writer takes a new name. Entries recorded before then keep the old one,
/// so a new name joins this set rather than replacing it (Nick, 16 Nov:
/// "It's an event, not an arrival", renamed by each owner).
final _eventKinds = {Kind.parse('arrived')!};

/// Runs the docking port until [follow]'s stream ends, which it never
/// should: the caller treats a return as the record going away.
///
/// It follows the record from its start, asking [follow] for its events
/// and its `admitted` and `declined` entries. Each event is read by the
/// one of [readings] for its source, in the record's order, and each
/// decision is taken into a [Decided]. Once [follow] has caught up, each
/// event with no decision is decided under [journeys] and [turns], in
/// order, and sent with [send] following the decision before it; so is
/// each event after that, as it comes.
///
/// When the record refuses a decision, [tipOf] says whether the decisions'
/// chain has moved on. If it has, another docking port decided first, and
/// its decision comes on the record to be taken like any other. If it
/// hasn't, the
/// refusal is for some other reason, such as a sender table that doesn't
/// allow the kind, and it is rethrown: deciding on regardless could admit
/// an event twice. A decision in the record that can't be read back stops
/// it too, for the same reason.
Future<void> runDockingPort({
  required Stream<FollowItem> Function(Set<Kind> kinds) follow,
  required Future<EntryHash> Function(
    Kind kind,
    EntryHash? follows,
    Uint8List body,
  )
  send,
  required Future<EntryHash> Function(EntryHash entry) tipOf,
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
  final decided = Decided();
  // Each event read but not yet decided, with its reading, in the record's
  // order.
  final waiting = <EntryHash, Reading?>{};

  // Decides each waiting event in order. Returns early when another
  // docking port has decided first: its decisions come on the record.
  Future<void> decideWaiting() async {
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
      final follows = decided.tip;
      final EntryHash entry;
      try {
        entry = await send(kind, follows, body);
      } on JournalWriteRefused {
        if (follows != null && await tipOf(follows) != follows) return;
        rethrow;
      }
      decided.take(entry, decision);
      waiting.remove(event);
    }
  }

  var caughtUp = false;
  final kinds = {..._eventKinds, DecisionKind.admitted, DecisionKind.declined};
  await for (final item in follow(kinds)) {
    switch (item) {
      case JournalEntryFrame(:final hash, :final kind)
          when _eventKinds.contains(kind):
        final event = Event.read(hash, item.body);
        waiting[hash] = switch (event) {
          final event? => folds[event.source]?.step(event),
          null => null,
        };
      case JournalEntryFrame(:final hash, :final kind):
        final decision =
            decodeDecision(kind, item.body) ??
            (throw StateError('cannot read the decision ${hash.hex}'));
        decided.take(hash, decision);
        waiting.remove(decision.event);
      case CaughtUp():
        caughtUp = true;
    }
    if (caughtUp) await decideWaiting();
  }
}

/// One module's reading, folded: it keeps the state the reading returned
/// last, and gives each event to the reading with it.
final class _Fold<S> {
  _Fold(this._reading) : _state = _reading.start;

  final ModuleReading<S> _reading;
  S _state;

  Reading step(Event event) {
    final (state, reading) = _reading.step(_state, event);
    _state = state;
    return reading;
  }
}
