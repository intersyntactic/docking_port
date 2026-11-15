/// The reading contract: what a module gives the docking port, and all it
/// gives.
///
/// A module takes part only by describing (RULINGS, "The docking port admits
/// arrivals under journey paths"). The docking port hands its
/// [ModuleReading] every arrival from the module's relay, in the record's
/// order, and for each the reading says what it is: a [Reading]. The
/// docking port never reads a module's bytes itself, and the module never
/// learns which journey path anything went to.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show ActorId;

/// One `arrived` entry, as the docking port gives it to a reading: the
/// entry's hash, and what its relay recorded, `{"at", "source", "bytes"}`.
///
/// Only [Arrival.read] makes one, from the entry's body as recorded.
final class Arrival {
  const Arrival._({
    required this.entry,
    required this.at,
    required this.source,
    required this.bytes,
  });

  /// The `arrived` entry's hash: what an admission and the turn made from
  /// it name the arrival by.
  final EntryHash entry;

  /// When the relay took it in.
  final DateTime at;

  /// The relay's name for where it came from, such as `teams`.
  final String source;

  /// The bytes exactly as they came.
  final Uint8List bytes;

  /// The `arrived` entry [entry], from its [body] as the relay recorded it.
  /// Null for anything else: it is our own wire, read strictly.
  static Arrival? read(EntryHash entry, Uint8List body) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    if (json
        case {
          'at': final String at,
          'source': final String source,
          'bytes': final String bytes,
        }
        when json.length == 3) {
      final when = DateTime.tryParse(at);
      final Uint8List raw;
      try {
        raw = base64Decode(bytes);
      } on FormatException {
        return null;
      }
      if (when == null || source.isEmpty) return null;
      return Arrival._(entry: entry, at: when, source: source, bytes: raw);
    }
    return null;
  }
}

/// A module's reading of its relay's arrivals, as a fold: the docking port
/// starts from [start] and calls [step] with each arrival from [source], in
/// the record's order, keeping only the state it returns.
///
/// [S] is the module's own, and the docking port never looks inside it. It
/// is there for what a reading needs from earlier arrivals: a quote's
/// author, the message an edit or delete is of, who an earlier join brought
/// in. On every start the docking port folds again from the record's
/// beginning, already-admitted arrivals included, so [step] must give the
/// same answer for the same arrivals in the same order, and must not change
/// the state it is given.
abstract interface class ModuleReading<S> {
  /// The [Arrival.source] whose arrivals this reads.
  String get source;

  /// The state before any arrival.
  S get start;

  /// [arrival] read, after every earlier one from [source] has been.
  (S, Reading) step(S state, Arrival arrival);
}

/// What one arrival is: something said ([Said]), a change to an earlier
/// message ([Changed]), a conversation joined ([Joined]), or nothing to
/// admit ([NothingToAdmit]).
sealed class Reading {
  const Reading();
}

/// Nothing to admit: a typing indicator, a reaction the module does not
/// carry, an activity it cannot read.
final class NothingToAdmit extends Reading {
  const NothingToAdmit();
}

/// An arrival the docking port may admit, and what it needs to decide
/// whether to.
sealed class Admissible extends Reading {
  const Admissible({
    required this.conversation,
    required this.from,
    required this.key,
  });

  /// The outside conversation it belongs to.
  final Conversation conversation;

  /// Who it comes from, or null for no one the module can name.
  final ActorId? from;

  /// What "not admitted twice" compares, within [conversation]: the same
  /// for every delivery of one event, and different for two events,
  /// including two changes to one message.
  final ArrivalKey key;
}

/// [message] was said. Whether it starts a turn is the docking port's
/// decision, under the journey path's rules.
final class Said extends Admissible {
  const Said({
    required super.conversation,
    required super.from,
    required super.key,
    required this.message,
  });

  /// The message, as the `UserSaid` made from it names it.
  final SourceMessageId message;
}

/// A change to [message], said earlier: an edit, or a delete. It is
/// matched to the arrival that said [message].
final class Changed extends Admissible {
  const Changed({
    required super.conversation,
    required super.from,
    required super.key,
    required this.message,
  });

  /// The message changed.
  final SourceMessageId message;
}

/// [joiners] joined [conversation]. One arrival may bring in several.
final class Joined extends Admissible {
  const Joined._({
    required super.conversation,
    required super.from,
    required super.key,
    required this.joiners,
  });

  /// Who joined; never empty.
  final List<ActorId> joiners;

  /// A join of [joiners]; null when there are none, which is
  /// [NothingToAdmit].
  static Joined? of({
    required Conversation conversation,
    required ActorId? from,
    required ArrivalKey key,
    required Iterable<ActorId> joiners,
  }) {
    final list = List<ActorId>.unmodifiable(joiners);
    if (list.isEmpty) return null;
    return Joined._(
      conversation: conversation,
      from: from,
      key: key,
      joiners: list,
    );
  }
}

/// An outside conversation: a Teams chat, a Slack channel. What the
/// docking port keeps under a journey path.
///
/// Written like an [ActorId], a source, a colon and the rest, such as
/// `teams:19:abc@thread.v2`, so two modules never name two conversations
/// alike.
final class Conversation {
  const Conversation._(this.value);

  /// The id, as text.
  final String value;

  /// [s] as a conversation; null unless it is a source, a colon, and the
  /// rest, with the rest printable ASCII and no spaces.
  static Conversation? parse(String s) =>
      _id.hasMatch(s) ? Conversation._(s) : null;

  static final _id = RegExp(r'^[a-z][a-z0-9-]*:[\x21-\x7e]+$');

  @override
  bool operator ==(Object other) =>
      other is Conversation && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One event's key within its conversation, in the module's own terms. Not
/// a message's id: an edit is a second event about the same message.
final class ArrivalKey {
  const ArrivalKey._(this.value);

  /// The key, as text.
  final String value;

  /// [s] as an arrival key; null when empty or with whitespace.
  static ArrivalKey? parse(String s) =>
      s.isNotEmpty && !s.contains(RegExp(r'\s')) ? ArrivalKey._(s) : null;

  @override
  bool operator ==(Object other) => other is ArrivalKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
