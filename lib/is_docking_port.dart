/// The docking port, a core piece of intersyntactic (RULINGS, "The docking
/// port admits arrivals under journey paths"): it reads arrivals from the
/// record in order and admits each one under a journey path, deciding which
/// journey path an outside conversation belongs to, whether an arrival
/// starts a turn, and that none is admitted twice.
///
/// So far: the reading contract, a module's [ModuleReading], a fold over
/// its relay's [Arrival]s that names what each one is, a [Reading]. The
/// [Decision] recorded for each arrival, [Admitted] or [Declined], as
/// [encodeDecision] writes it and [decodeDecision] reads it back; [decide],
/// which makes one under the rules passed in, [JourneyRule] and [TurnRule];
/// and [Decided], what the decisions add up to when read back.
///
/// Not here yet: following the record and sending decisions to it, and
/// handing an arrival to a journey path's apex.
library;

export 'src/decide.dart';
export 'src/decided.dart';
export 'src/decision.dart';
export 'src/decision_wire.dart';
export 'src/reading.dart';
export 'src/rules.dart';
