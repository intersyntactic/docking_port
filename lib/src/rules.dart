/// The rules the docking port decides by, passed in: which journey path a
/// conversation goes under, and whether something said starts a turn. Both
/// are calls still open, so neither is written here.
///
/// A rule is asked at most once per event, in the record's order, and what
/// it answered is kept in the decision, never asked again on a restart. So
/// a rule can change between restarts without changing anything it already
/// decided.
library;

import 'decision.dart';
import 'reading.dart';

/// Which journey path a conversation goes under. Asked when an admissible
/// arrival names a conversation that is under none yet; a change is never
/// placed, since it goes where the message it changes went.
abstract interface class PlacementRule {
  /// Where [first] and the rest of its conversation go, or null for
  /// nowhere: [first] is then [NotPlaced], and the conversation's next
  /// event is asked about again.
  Placement? place(Admissible first);
}

/// Whether something said starts a turn: a person's turn, in a journey
/// path's terms, which the agent then takes its own turn in answer to.
abstract interface class TurnRule {
  /// Whether [said] starts a turn under [placement]. When it doesn't, it
  /// is [NotATurn], and a conversation not yet under a journey path stays
  /// under none.
  bool startsTurn(Said said, Placement placement);
}
