/// Running the docking port: following the record, deciding each arrival,
/// and sending each decision to it (RULINGS, "The docking port admits
/// arrivals under journey paths").
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

/// The kind of entry a relay records an arrival as.
final _arrived = Kind.parse('arrived')!;

/// Runs the docking port until [follow]'s stream ends, which it never
/// should: the caller treats a return as the record going away.
///
/// It follows the record from its start, asking [follow] for its
/// `arrived`, `admitted` and `declined` entries. Each arrival is read by
/// the one of [readings] for its source, in the record's order, and each
/// decision is taken into a [Decided]. Once [follow] has caught up, each
/// arrival with no decision is decided under [journeys] and [turns], in
/// order, and sent with [send] following the decision before it; so is
/// each arrival after that, as it comes.
///
/// When the record refuses a decision, [tipOf] says whether the decisions'
/// chain has moved on. If it has, another docking port decided first, and
/// its decision arrives to be taken like any other. If it hasn't, the
/// refusal is for some other reason, such as a sender table that doesn't
/// allow the kind, and it is rethrown: deciding on regardless could admit
/// an arrival twice. A decision in the record that can't be read back
/// stops it too, for the same reason.
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
  // Each arrival read but not yet decided, with its reading, in the
  // record's order.
  final waiting = <EntryHash, Reading?>{};

  // Decides each waiting arrival in order. Returns early when another
  // docking port has decided first: its decisions arrive on the record.
  Future<void> decideWaiting() async {
    while (waiting.isNotEmpty) {
      final MapEntry(key: arrival, value: reading) = waiting.entries.first;
      final decision = decide(
        arrival,
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
      waiting.remove(arrival);
    }
  }

  var caughtUp = false;
  final kinds = {_arrived, DecisionKind.admitted, DecisionKind.declined};
  await for (final item in follow(kinds)) {
    switch (item) {
      case JournalEntryFrame(:final hash, :final kind) when kind == _arrived:
        final arrival = Arrival.read(hash, item.body);
        waiting[hash] = switch (arrival) {
          final arrival? => folds[arrival.source]?.step(arrival),
          null => null,
        };
      case JournalEntryFrame(:final hash, :final kind):
        final decision =
            decodeDecision(kind, item.body) ??
            (throw StateError('cannot read the decision ${hash.hex}'));
        decided.take(hash, decision);
        waiting.remove(decision.arrival);
      case CaughtUp():
        caughtUp = true;
    }
    if (caughtUp) await decideWaiting();
  }
}

/// One module's reading, folded: it keeps the state the reading returned
/// last, and gives each arrival to the reading with it.
final class _Fold<S> {
  _Fold(this._reading) : _state = _reading.start;

  final ModuleReading<S> _reading;
  S _state;

  Reading step(Arrival arrival) {
    final (state, reading) = _reading.step(_state, arrival);
    _state = state;
    return reading;
  }
}
