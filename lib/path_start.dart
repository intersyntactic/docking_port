/// The docking station's `event-admitted-to-mission` entries read for the
/// trajectories they start and those trajectories' rules:
/// [readTrajectoryStart]. For the airlock, which imports this and not
/// `is_docking_station.dart`, so that what strangers sent is never decoded in
/// it (airlock-api-04 and Nick, 16 Nov).
///
/// Its imports stay is_logbook and is_shapes; test/path_start_imports_test
/// fails if anything else comes in.
library;

export 'src/path_start.dart';
