## 0.1.0

- First release on pub.dev. Reads events from the record in order and writes
  one decision for each: admitted to a mission (starting a trajectory, on one,
  or into a mission), not admitted, or the mission ended.
- `readTrajectoryStart` in `path_start.dart`, the airlock's narrow reader of a
  trajectory's start entry.
- On is_shapes ^0.6.0, is_conversation_shapes ^0.8.3, is_annotation_shapes
  ^0.3.2, is_logbook ^0.2.1 and is_logbook_client ^0.2.0.
