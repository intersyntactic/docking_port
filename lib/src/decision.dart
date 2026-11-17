/// What the docking station decides about each event, each sent to the record
/// as an entry of its own (RULINGS, "The docking station admits events under
/// trajectories").
///
/// Every event is decided exactly once: [EventAdmittedToMission] under a
/// trajectory, or [EventNotAdmittedToMission], saying why. A decline is
/// recorded as well as an admission, so on a restart the docking station reads
/// back what it decided rather than deciding again. An event with no decision
/// is one it had not reached, never one it turned away, so a reading or a rule
/// changed since cannot admit an old event it once kept out.
///
/// The decisions are one chain in the record, each naming the one before it
/// as previous. The record refuses an entry whose previous is not its
/// chain's tip, so two docking stations that each believe they hold the
/// chain cannot both decide one event: the second is refused, reads the
/// first one's decision back, and goes on. "None is admitted twice" is the
/// record's guarantee, not a set one process keeps. It holds for the first
/// decision too, since its previous is the start entry rather than none: the
/// record starts a new chain for any entry with no previous, so two docking
/// stations making a first decision with none would start two.
///
/// Each decision holds what it was decided on (the address, the
/// event's key, the message), so the docking station's state is rebuilt from
/// its decisions alone, whatever a module's reading would make of an old
/// event now.
library;

import 'package:checked_json/checked_json.dart' show JsonObject;
import 'package:is_conversation_shapes/is_conversation_shapes.dart'
    show SourceMessageId;
import 'package:is_journal/is_journal.dart' show EntryHash;
import 'package:is_journal/service.dart' show Kind;
import 'package:is_shapes/is_shapes.dart'
    show ActorId, DecidedBy, JourneyId, JourneyPathId;

import 'reading.dart';
import 'rules.dart';

/// The kinds of entry the docking station sends, one per event. Its user's
/// row in the record's sender table allows these three and nothing else.
abstract final class DecisionEntryKind {
  /// An [EventAdmittedToMission]'s kind.
  static final eventAdmittedToMission = Kind.parse(
    'event-admitted-to-mission',
  )!;

  /// A [EventNotAdmittedToMission]'s kind.
  static final eventNotAdmittedToMission = Kind.parse(
    'event-not-admitted-to-mission',
  )!;

  /// A [MissionEnded]'s kind, the journal's own word: it reads it to close
  /// the mission's chains.
  // TODO(0.10.0): Kind.missionEnded
  static final missionEnded = Kind.parse('mission-ended')!;

  /// Every kind above, as the docking station subscribes to its own
  /// decisions.
  static final all = {
    eventAdmittedToMission,
    eventNotAdmittedToMission,
    missionEnded,
  };
}

/// Where an admitted event goes. Something said, or a change, goes
/// [OnTrajectory] a trajectory already started, or
/// [StartsTrajectory], a new one its admission starts. A join goes
/// [IntoMission]: it says who is in a mission, and is under none of its
/// trajectories.
sealed class AdmittedPlacement {
  const AdmittedPlacement();
}

/// Under [trajectory], in the mission it was started in.
final class OnTrajectory extends AdmittedPlacement {
  const OnTrajectory(this.trajectory);

  final JourneyPathId trajectory;
}

/// Under a new trajectory in [mission], which the admission starts and is named
/// by: its id is the hash of the `event-admitted-to-mission` entry that started
/// it. A [JourneyPathId] is given by whoever starts the trajectory, and here
/// that is the docking station, so the entry that started it is its one name,
/// the way a turn's id is the hash of its entry.
final class StartsTrajectory extends AdmittedPlacement {
  const StartsTrajectory(this.mission);

  final MissionPlacement mission;
}

/// Into [mission]: a join, which is about who is in it.
final class IntoMission extends AdmittedPlacement {
  const IntoMission(this.mission);

  final MissionPlacement mission;
}

/// Which mission: [InMission], one already started, or [StartsMission], a new
/// one the admission starts. A mission the docking station starts is named like
/// a trajectory it starts, by the `event-admitted-to-mission` entry's hash, as
/// a [JourneyId]. One entry can start both, as a chat's first message does, and
/// then both have its hash, as two kinds of name.
sealed class MissionPlacement {
  const MissionPlacement();
}

/// In [mission], already started.
final class InMission extends MissionPlacement {
  const InMission(this.mission);

  final JourneyId mission;
}

/// In a new mission, which the admission starts.
final class StartsMission extends MissionPlacement {
  const StartsMission();
}

/// What the docking station decided about the event recorded at [event], and
/// [by] whom, so the record tells "the rules let it through" from "the
/// person said yes", as the airlock's does.
///
/// Every entry says who, as `"by": <who>`, where `<who>` is `rules` or
/// `person`.
sealed class AdmissionDecision {
  const AdmissionDecision(this.event, {required this.by});

  /// The event decided, by its entry's hash.
  final EntryHash event;

  /// Who decided it.
  final DecidedBy by;
}

/// [event], read as [reading], admitted by [placement].
///
/// The entry, of kind `event-admitted-to-mission`:
///
///     {"event": <hex>, "by": <who>, "reading": <reading>,
///      ...the placement, "rules": <rules>?, "startsTurn": <bool>?}
///
/// `<reading>` is the whole reading, as [encodeReading] writes it (Nick,
/// 16 Nov: the entry that admits it carries the reading), so whatever hands
/// the event to its trajectory's crux reads the node from the decision, and
/// never reads a module's bytes. The placement is `"trajectory": <id>` for
/// [OnTrajectory]; `"startsTrajectory": true` and the mission for
/// [StartsTrajectory]; the mission alone for [IntoMission]. The mission is
/// `"mission": <id>` for [InMission], or `"startsMission": true` for
/// [StartsMission].
///
/// [rules] are there exactly when the admission starts a mission or a
/// trajectory: the rules the mission was admitted under, as the [JourneyRule]
/// gave them, copied into each trajectory it starts. loop_launcher reads a
/// trajectory's rules from the entry that started it, and the airlock enforces
/// them; the docking station passes them through unread.
///
/// [startsTurn] is there exactly when the reading is [MessageSaid]: whether the
/// agent answers it, as the [TurnRule] said. Something said that starts no turn
/// is still admitted under its address's trajectory, so the agent has it as
/// context (Nick, 16 Nov: "yeah that sounds right", to admitting it rather than
/// declining it). It never starts a trajectory, since a trajectory brings up an
/// agent loop: one that starts no turn where its address has no trajectory yet
/// is [SaidStartsNoTurn].
///
/// The reading's [containingAddress] is kept so which mission an address in an
/// external system is can be rebuilt from decisions alone; its [from], for
/// rules about who starts turns, such as a cap on turns bots start.
final class EventAdmittedToMission extends AdmissionDecision {
  /// Throws an [ArgumentError] when [rules] are given for an admission
  /// that starts nothing, or missing for one that starts something; when
  /// [startsTurn] is given for anything but something said, or missing for
  /// something said; and when something said starts a trajectory but no
  /// turn.
  EventAdmittedToMission(
    super.event, {
    required super.by,
    required this.reading,
    required this.placement,
    this.rules,
    this.startsTurn,
  }) {
    if ((rules != null) != starts(placement)) {
      throw ArgumentError.value(
        rules,
        'rules',
        'given exactly when the admission starts a mission or a trajectory',
      );
    }
    if ((startsTurn != null) != (reading is MessageSaid)) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'given exactly when the reading is something said',
      );
    }
    if (placement is StartsTrajectory && startsTurn == false) {
      throw ArgumentError.value(
        startsTurn,
        'startsTurn',
        'something said that starts no turn starts no trajectory',
      );
    }
  }

  final AdmissibleEvent reading;
  final AdmittedPlacement placement;
  final JsonObject? rules;

  /// Whether the agent answers it: for something said, and null for
  /// anything else.
  final bool? startsTurn;

  /// Whether [placement] starts a trajectory or a mission.
  static bool starts(AdmittedPlacement placement) => switch (placement) {
    StartsTrajectory() || IntoMission(mission: StartsMission()) => true,
    OnTrajectory() || IntoMission(mission: InMission()) => false,
  };

  AddressInExternalSystem get addressInExternalSystem =>
      reading.addressInExternalSystem;
  AddressInExternalSystem? get containingAddress => reading.containingAddress;
  EventKey get key => reading.key;
  ActorId? get from => reading.from;

  /// The message it says, changes or judges; null for a join.
  SourceMessageId? get message => switch (reading) {
    MessageSaid(:final message) || MessageChanged(:final message) => message,
    ShownMessageJudged(:final to) => to,
    ActorsJoinedAddress() => null,
  };
}

/// [mission] ended, at [event]: its loops stop, its programs close and its
/// users are freed (loop_launcher), and the record takes nothing more on its
/// trajectories' chains (is_journal). The person's next message in it opens it
/// again, on a new trajectory (RULINGS).
///
/// The docking station ends missions (Nick, 16 Nov, of journeys since
/// renamed missions: "probably the docking station should end a journey,
/// no?", and not as a tool of the agent's). What event ends one is not
/// decided yet, so nothing decides one here; it is read back like any other
/// decision.
///
/// The entry, of kind `mission-ended`:
///
///     {"event": <hex>, "by": <who>, "mission": <id>}
final class MissionEnded extends AdmissionDecision {
  const MissionEnded(super.event, {required super.by, required this.mission});

  final JourneyId mission;
}

/// [event] not admitted to any mission: nothing comes of it, and nothing
/// will, whatever
/// changes later. The case says why.
///
/// The entry, of kind `event-not-admitted-to-mission`:
///
///     {"event": <hex>, "by": <who>, "why": <case>, ...the case's own fields}
///
/// `<case>` is `no-reading-for-source`, `reading-found-nothing`,
/// `duplicate-event`, `address-not-admitted-to-mission`,
/// `said-starts-no-turn`, `judged-message-has-no-trajectory` or
/// `change-to-unadmitted-message`.
sealed class EventNotAdmittedToMission extends AdmissionDecision {
  const EventNotAdmittedToMission(super.event, {required super.by});
}

/// No reading takes the event's source, or its body is not what a relay
/// records. A source whose module has no reading yet has its events
/// not admitted, so a reading added later starts from the events after it.
final class NoReadingForSource extends EventNotAdmittedToMission {
  const NoReadingForSource(super.event, {required super.by});
}

/// The module's reading found nothing to admit.
final class ReadingFoundNothing extends EventNotAdmittedToMission {
  const ReadingFoundNothing(super.event, {required super.by});
}

/// An event a reading named by its key, not admitted. A key is decided once,
/// whichever way it went, so a second event with the same key is a
/// [DuplicateEvent], even when the first was not admitted.
sealed class NotAdmittedKeyedEvent extends EventNotAdmittedToMission {
  const NotAdmittedKeyedEvent(
    super.event, {
    required super.by,
    required this.addressInExternalSystem,
    required this.key,
  });

  final AddressInExternalSystem addressInExternalSystem;
  final EventKey key;
}

/// [key] in [addressInExternalSystem] was decided already, at the event [of]:
/// its relay recorded one thing twice, as two events with one key.
/// `"of": <hex>`.
final class DuplicateEvent extends NotAdmittedKeyedEvent {
  const DuplicateEvent(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
    required this.of,
  });

  final EntryHash of;
}

/// [addressInExternalSystem]'s mission hasn't started, and the
/// [JourneyRule] doesn't admit it. The next event from it is asked about
/// again.
final class AddressNotAdmittedToMission extends NotAdmittedKeyedEvent {
  const AddressNotAdmittedToMission(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// Something said that the turn rule says starts no turn, in an address
/// with no trajectory yet. Where it has one, it is admitted, with
/// [EventAdmittedToMission.startsTurn] false.
final class SaidStartsNoTurn extends NotAdmittedKeyedEvent {
  const SaidStartsNoTurn(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// A verdict in [addressInExternalSystem], which is under no trajectory, so no
/// turn of the agent's there could have shown what was judged.
final class JudgedMessageHasNoTrajectory extends NotAdmittedKeyedEvent {
  const JudgedMessageHasNoTrajectory(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
  });
}

/// A change to [message], which was never admitted, or was admitted in a
/// mission since ended, so there is no turn for it to change.
/// `"message": <source>`.
final class ChangeToUnadmittedMessage extends NotAdmittedKeyedEvent {
  const ChangeToUnadmittedMessage(
    super.event, {
    required super.by,
    required super.addressInExternalSystem,
    required super.key,
    required this.message,
  });

  final SourceMessageId message;
}
