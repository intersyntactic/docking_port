/// The reading contract: what a module gives the docking station, and all it
/// gives.
///
/// A module takes part only by describing (RULINGS, "The docking station admits
/// events under journey paths"). The docking station hands its
/// [ModuleReading] every event from the module's relay, in the record's
/// order, and for each the reading says what it is: a [Reading]. The
/// docking station never reads a module's bytes itself, and the module never
/// learns which journey path anything went to.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:is_annotation_shapes/is_annotation_shapes.dart'
    show VerdictOnShownMessage;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId, UserSaid, WhatChanged;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_shapes/is_shapes.dart' show ActorId;

/// One event, as the docking station gives it to a reading: its entry's hash,
/// and what its relay recorded, `{"at", "source", "bytes"}`, as an entry of
/// kind `event`, or `arrived` if it was recorded before the rename (Nick,
/// 16 Nov: "It's an event, not an arrival").
///
/// Only [Event.read] makes one, from the entry's body as recorded.
final class Event {
  const Event._({
    required this.entry,
    required this.at,
    required this.source,
    required this.bytes,
  });

  /// The entry's hash: what an admission and the turn made from it name
  /// the event by.
  final EntryHash entry;

  /// When the relay took it in.
  final DateTime at;

  /// The relay's name for where it came from, such as `teams`.
  final String source;

  /// The bytes exactly as they came.
  final Uint8List bytes;

  /// The event recorded at [entry], from its [body] as the relay recorded it.
  /// Null for anything else: it is our own wire, read strictly.
  static Event? read(EntryHash entry, Uint8List body) {
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
      return Event._(entry: entry, at: when, source: source, bytes: raw);
    }
    return null;
  }
}

/// A module's reading of its relay's events, as a fold: the docking station
/// starts from [start] and calls [step] with each event from [source], in
/// the record's order, keeping only the state it returns.
///
/// [S] is the module's own, and the docking station never looks inside it. It
/// is there for what a reading needs from earlier events: a quote's
/// author, the message an edit or delete is of, who an earlier join brought
/// in. On every start the docking station folds again from the record's
/// beginning, already-admitted events included, so [step] must give the
/// same answer for the same events in the same order, and must not change
/// the state it is given.
abstract interface class ModuleReading<S> {
  /// The [Event.source] whose events this reads.
  String get source;

  /// The state before any event.
  S get start;

  /// [event] read, after every earlier one from [source] has been.
  (S, Reading) step(S state, Event event);
}

/// What one event is: something said ([Said]), a change to an earlier
/// message ([Changed]), a conversation joined ([Joined]), a person's verdict
/// on something the agent showed ([Judged]), or nothing to admit
/// ([NothingToAdmit]).
sealed class Reading {
  const Reading();
}

/// Nothing to admit: a typing indicator, a reaction the module does not
/// carry, an activity it cannot read.
final class NothingToAdmit extends Reading {
  const NothingToAdmit();
}

/// An event the docking station may admit, and what it needs to decide
/// whether to.
sealed class Admissible extends Reading {
  const Admissible({
    required this.conversation,
    required this.within,
    required this.key,
  });

  /// The outside conversation it belongs to.
  final Conversation conversation;

  /// The conversation [conversation] sits inside, such as the channel a
  /// thread is in. Null when it sits inside none, as a chat or a channel
  /// itself does.
  ///
  /// It is what the outside groups its conversations by: a channel is a
  /// journey and each of its threads a journey path (Nick, 2026-11-15:
  /// "channel = journey, thread = journey path"). The reading names it so
  /// the docking station never reads a module's ids to find it.
  final Conversation? within;

  /// Who it comes from, or null for no one the module can name.
  ActorId? get from;

  /// What "not admitted twice" compares, within [conversation]: the same
  /// for two events that record one thing, as a redelivery does, and
  /// different for two things, including two changes to one message.
  final EventKey key;
}

/// Something said, as [node], the node the journey path's apex appends.
/// Whether it starts a turn is the docking station's decision, under the
/// journey path's rules.
///
/// The reading builds [node] because only its fold holds what that takes,
/// such as who wrote a message it quotes (Nick, 2026-11-15: the reading
/// carries the node). Someone the module can't name has said nothing it
/// can admit, since a [UserSaid] always has an author.
final class Said extends Admissible {
  const Said({
    required super.conversation,
    required super.within,
    required super.key,
    required this.node,
  });

  /// What was said.
  final UserSaid node;

  @override
  ActorId get from => node.author;

  /// The message, as [node] names it.
  SourceMessageId get message => node.source;
}

/// A change to [message], said earlier: an edit, a delete or a restore, as
/// [change] says. It is matched to the event that said [message].
///
/// It is admitted whoever made it. Whether it counts is for whatever reads
/// it: a change counts only when [from] is who said [message] (Nick, 16
/// Nov, the rule `Withdrawal` keeps).
final class Changed extends Admissible {
  const Changed({
    required super.conversation,
    required super.within,
    required this.from,
    required super.key,
    required this.message,
    required this.change,
  });

  @override
  final ActorId? from;

  /// The message changed.
  final SourceMessageId message;

  /// What [message] became: what it says now, or that it was deleted or
  /// restored, in message terms, before anything maps it to a turn.
  final WhatChanged change;
}

/// [joiners] joined [conversation]. One event may bring in several.
final class Joined extends Admissible {
  const Joined._({
    required super.conversation,
    required super.within,
    required this.from,
    required super.key,
    required this.joiners,
  });

  @override
  final ActorId? from;

  /// Who joined; never empty.
  final List<ActorId> joiners;

  /// A join of [joiners]; null when there are none, which is
  /// [NothingToAdmit].
  static Joined? of({
    required Conversation conversation,
    required Conversation? within,
    required ActorId? from,
    required EventKey key,
    required Iterable<ActorId> joiners,
  }) {
    final list = List<ActorId>.unmodifiable(joiners);
    if (list.isEmpty) return null;
    return Joined._(
      conversation: conversation,
      within: within,
      from: from,
      key: key,
      joiners: list,
    );
  }
}

/// A person's [verdict] on [to], something the agent showed them, such as
/// Approve, Not yet or a proposed correction on a card (Nick, 2026-11-15;
/// named `Judged` 16 Nov). Named for what the person said, not for the
/// button, so a Slack button reads the same.
///
/// It names the message, never a turn: the journey path's apex builds the
/// annotation, a `NodeApproval`, a `NodeSeenMark` or a `NodeCorrection`,
/// once it knows which turn [to] showed. A verdict always names who gave it, since a
/// verdict from no one approves nothing.
final class Judged extends Admissible {
  const Judged({
    required super.conversation,
    required super.within,
    required this.from,
    required super.key,
    required this.to,
    required this.verdict,
  });

  @override
  final ActorId from;

  /// The message judged, such as the card, as it was sent.
  final SourceMessageId to;

  final VerdictOnShownMessage verdict;
}

/// An outside conversation: a Teams chat, channel or channel thread, a
/// Slack channel. The docking station keeps each one under a journey path,
/// and one that others sit inside, such as a channel, as a journey.
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
final class EventKey {
  const EventKey._(this.value);

  /// The key, as text.
  final String value;

  /// [s] as an event key; null when empty or with whitespace.
  static EventKey? parse(String s) =>
      s.isNotEmpty && !s.contains(RegExp(r'\s')) ? EventKey._(s) : null;

  @override
  bool operator ==(Object other) => other is EventKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
