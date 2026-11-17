/// The docking station, a core piece of intersyntactic (RULINGS, "The docking
/// station admits events under journey paths"): it reads events from the record
/// in order and admits each one under a trajectory, deciding which trajectory
/// an address in an external system belongs to, whether an event starts a turn,
/// and that none is admitted twice.
///
/// So far: the reading contract, a module's [ModuleReading], a fold over its
/// relay's [RelayedEvent]s that names what each one is, an [EventReading]. The
/// [AdmissionDecision] recorded for each event, [EventAdmittedToMission] or
/// [EventNotAdmittedToMission], and [MissionEnded], as [encodeDecision] writes
/// it and [decodeDecision] reads it back; [decide], which makes one under the
/// rules passed in, [JourneyRule] and [TurnRule]; [DecidedSoFar], what the
/// decisions add up to when read back; and [runDockingStation], which
/// subscribes to the record and sends each decision to it.
///
/// Not here yet: handing an event to a trajectory's apex.
library;

export 'src/decide.dart';
export 'src/decided.dart';
export 'src/decision.dart';
export 'src/decision_wire.dart';
export 'src/reading.dart';
export 'src/reading_wire.dart';
export 'src/rules.dart';
export 'src/run.dart';
