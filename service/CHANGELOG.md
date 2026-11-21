Each version is tagged `service-vX.Y.Z` on the commit it is built from, and a
deploy names the tag.

## 0.1.0

- The first versioned release of the docking station service.
- Flight rules are chosen by mission address: `--flight-rules` reads
  `{"default", "byMissionAddress"}`, each an is_flight_rules 0.3.0
  `FlightRules` with a required starting model.
- On is_docking_station 0.3.0. Pins teams_module 21a88bd, where every reading
  names the bot it was sent to (`addressedTo`) and a "Close trajectory"
  action on any message closes the trajectory at its address.
- A test builds the program with every module it pins.
