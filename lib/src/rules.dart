/// The rules the docking station decides by, passed in: whether an outside
/// conversation comes in at all, and whether something said starts a turn.
/// Both are calls still open, so neither is written here.
///
/// Where an event goes is not a rule. A conversation goes under a journey
/// path of its own, in the journey of what it sits within, or its own
/// journey when it sits within nothing (Nick, 2026-11-15: "channel =
/// journey, thread = journey path"). A change goes where the message it
/// changes went; a verdict goes under its conversation's journey path,
/// since what it judges was shown there.
///
/// A rule is asked at most once per event, in the record's order, and what
/// it answered is kept in the decision, never asked again on a restart. So
/// a rule can change between restarts without changing anything it already
/// decided.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;

import 'decision.dart';
import 'reading.dart';

/// Whether an outside conversation whose journey hasn't started comes in.
/// Asked for the first admissible event of the conversation a journey is:
/// what threads sit within, or a conversation that sits within nothing,
/// such as a chat. Once it has come in, the conversations within it come in
/// with it, without asking.
abstract interface class JourneyRule {
  /// The rules [first]'s journey is taken in under, or null when it isn't
  /// taken in. Then [first] is [NotTakenIn], and the conversation's next
  /// event is asked about again.
  ///
  /// The rules are what the airlock enforces on each of the journey's
  /// paths, and the docking station never reads them: it records them in
  /// the entry that starts the journey, and copies them into each entry
  /// that starts one of its paths, where loop_launcher reads them (Nick,
  /// 16 Nov: the entry that starts a path records its rules).
  JsonObject? takeIn(Admissible first);
}

/// Whether something said starts a turn: a person's turn, in a journey
/// path's terms, which the agent then takes its own turn in answer to.
abstract interface class TurnRule {
  /// Whether [said] starts a turn under [placement]. When it doesn't, it
  /// is [NotATurn], and nothing it would have started is started.
  bool startsTurn(Said said, Placement placement);
}
