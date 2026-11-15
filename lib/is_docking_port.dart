/// The docking port, a core piece of intersyntactic (RULINGS, "The docking
/// port admits arrivals under journey paths"): it reads arrivals from the
/// record in order and admits each one under a journey path, deciding which
/// journey path an outside conversation belongs to, whether an arrival
/// starts a turn, and that none is admitted twice.
///
/// So far, the reading contract: a module's [ModuleReading], a fold over
/// its relay's [Arrival]s that names what each one is, a [Reading]. And,
/// as types to agree on before the logic: the [Decision] recorded for each
/// arrival, [Admitted] or [Declined]; the rules passed in, [PlacementRule]
/// and [TurnRule]; and [Decided], what the decisions add up to when read
/// back.
///
/// Not here yet: deciding, the decision entries' bytes, and handing an
/// arrival to a journey path's apex.
library;

export 'src/decided.dart';
export 'src/decision.dart';
export 'src/reading.dart';
export 'src/rules.dart';
