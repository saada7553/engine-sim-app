# Engine & Transmission Configuration Options (.mr Reference)

This report enumerates every parameter the C++ simulator currently consumes
through the `.mr` (Piranha SDL) configuration files. It is the authoritative
list for designing an **Engine Build / Transmission Build UI** — only options
listed here are actually wired into the native side. Anything else would be
purely cosmetic until the C++ backend is extended.

Sources:
- Schema: `physics-simulation/engine-sim/es/objects/objects.mr`
- Actions: `physics-simulation/engine-sim/es/actions/actions.mr`
- Native bindings: `physics-simulation/engine-sim/include/{engine,vehicle,transmission}.h`
- Reference engines: `physics-simulation/engine-sim/assets/engines/**/*.mr`

---

## 1. Top-Level Composition

An engine `.mr` is built bottom-up by chaining together the following objects.
The build UI should follow the same hierarchy:

```
engine
├── fuel
├── throttle (direct_throttle_linkage OR governor)
├── crankshaft(s)               .add_rod_journal(...) ...
├── cylinder_bank(s)            .add_cylinder(...).set_cylinder_head(...)
│       ├── piston (per cylinder)
│       ├── connecting_rod (per cylinder)
│       ├── intake (shared or per-cylinder)
│       ├── exhaust_system (shared or per-bank)
│       ├── ignition_wire (per cylinder)
│       └── cylinder_head
│             └── valvetrain (standard OR vtec)
│                   ├── intake_camshaft
│                   └── exhaust_camshaft (each with lobe_profile + lobes)
└── ignition_module (timing_curve, rev_limit) → connect_wire(angle)

vehicle  (mass, drag, diff, tire, rolling resistance)
transmission (max_clutch_torque, .add_gear(ratio) ...)
```

`set_engine`, `set_vehicle`, and `set_transmission` actions wire the three
units into the simulator at the end of the file.

---

## 2. Engine Block (top-level `engine`)

Source: `objects.mr` lines 67–137. Defaults shown in parentheses.

| Field | Type / Units | Default | Notes |
|---|---|---|---|
| `name` | string | `""` | Display name. |
| `redline` | float (RPM) | `6000 rpm` | Hard redline used by UI/dyno. |
| `starter_speed` | float (RPM) | `200 rpm` | Cranking speed. |
| `starter_torque` | float (torque) | `200 lb-ft` | Cranking torque. |
| `dyno_min_speed` | float (RPM) | `1000 rpm` | Dyno sweep start. |
| `dyno_max_speed` | float (RPM) | `redline` | Dyno sweep end. |
| `dyno_hold_step` | float (RPM) | `100 rpm` | Dyno hold/step granularity. |
| `fuel` | fuel | `fuel()` | See §3. |
| `throttle_gamma` | float | `1.0` | Throttle response curve (used when default linkage is generated). |
| `throttle` | throttle_channel | `direct_throttle_linkage(gamma)` | Can be replaced with `governor` (see §4). |
| `simulation_frequency` | float (Hz) | `10000` | Internal sim step rate. |
| `hf_gain` | float | `0.01` | High-frequency audio gain. |
| `jitter` | float | `0.5` | Audio jitter coefficient. |
| `noise` | float | `1.0` | Audio noise floor. |

The native `Engine::Parameters` struct (`engine.h:25`) confirms these are all
the engine-wide knobs the C++ side reads.

---

## 3. Fuel (`fuel`)

`objects.mr:51`. Models combustion behavior, not just chemistry.

| Field | Units | Default |
|---|---|---|
| `name` | string | `"Gasoline [Default]"` |
| `molecular_mass` | mass | `100 g` |
| `energy_density` | energy/mass | `48.1 kJ/g` |
| `density` | mass/volume | `0.755 kg/L` |
| `molecular_afr` | ratio | `12.5` |
| `turbulence_to_flame_speed_ratio` | function | sample curve (see file) |
| `max_burning_efficiency` | float | `0.8` |
| `burning_efficiency_randomness` | float | `0.5` |
| `low_efficiency_attenuation` | float | `0.6` |
| `max_turbulence_effect` | float | `2.0` |
| `max_dilution_effect` | float | `10.0` |

**UI suggestion:** offer a fuel preset selector (Gasoline / E85 / Methanol /
Diesel) that fills these fields, plus an "advanced" panel for direct edits.
The `turbulence_to_flame_speed_ratio` is a curve — expose as either a preset
or a graphical editor (same pattern used for the cam lobe / port flow / timing
curves below).

---

## 4. Throttle

Two valid forms — pick one per engine:

**`direct_throttle_linkage`** (`objects.mr:139`)
- `gamma` (float, default `1.0`) — response exponent.

**`governor`** (`objects.mr:144`) — closed-loop RPM governor.
- `min_speed`, `max_speed` (float)
- `min_v`, `max_v` (float)
- `k_s` (float, default `1.0`) — spring constant.
- `k_d` (float, default `300.0`) — damping.
- `gamma` (float, default `0.1`)

---

## 5. Crankshaft (`crankshaft`)

`objects.mr:179`. One or more per engine (`engine.add_crankshaft(...)`).

| Field | Units |
|---|---|
| `throw` | length (= stroke / 2) |
| `flywheel_mass` | mass |
| `mass` | mass |
| `friction_torque` | torque |
| `moment_of_inertia` | mass·length² |
| `position_x`, `position_y` | length (display layout) |
| `tdc` | angle (orients the crank in the engine) |

Rod journals are attached with `.add_rod_journal(rod_journal(angle: …))`.

**UI suggestion:** for a simple build flow, derive `throw = stroke/2`,
`moment_of_inertia` via the existing helper `disk_moment_of_inertia(mass,
radius)` + flywheel disk inertia (this is what every reference engine does
— see `07_gm_ls.mr:177-194`). Expose: stroke, crank mass, flywheel
mass, flywheel radius, friction torque, TDC offset. The journal angles are
determined by firing order and bank count — should be UI-generated, not hand
entered.

---

## 6. Rod Journals & Connecting Rods

`rod_journal` (`objects.mr:203`)
- `angle` (angle): position on the crank.

`connecting_rod_parameters` (`objects.mr:217`)

| Field | Units |
|---|---|
| `mass` | mass |
| `moment_of_inertia` | computed via `rod_moment_of_inertia(mass, length)` |
| `center_of_mass` | length |
| `length` | length |
| `slave_throw` | length (for master/slave rod setups, e.g. radials) |

---

## 7. Piston (`piston_parameters`)

`objects.mr:248`.

| Field | Units |
|---|---|
| `mass` | mass |
| `blowby` | flow coefficient (typically `k_28inH2O(x)`) |
| `compression_height` | length |
| `wrist_pin_position` | length |
| `wrist_pin_location` | length |
| `displacement` | length (piston-dome offset — *not* engine displacement) |

---

## 8. Cylinder Bank (`cylinder_bank_parameters`)

`objects.mr:280`. One per bank (inline = 1 bank, V = 2 banks, etc.).

| Field | Units |
|---|---|
| `angle` | angle (bank angle, e.g. ±45° for a 90° V) |
| `bore` | length |
| `deck_height` | length (= `stroke/2 + rod_length + compression_height`) |
| `position_x`, `position_y` | length (display layout) |
| `display_depth` | float (`0.5` default — rendering only) |

Cylinders are attached with `.add_cylinder(piston, connecting_rod,
rod_journal, intake, exhaust_system, ignition_wire, sound_attenuation,
primary_length)` — see `actions.mr:85`.

Per-cylinder add_cylinder inputs:
- `sound_attenuation` (float, default `1.0`)
- `primary_length` (length, default `0`) — exhaust primary tube length to
  collector; used for audio timing.

---

## 9. Cylinder Head (`cylinder_head_parameters`)

`objects.mr:362`.

| Field | Units | Default |
|---|---|---|
| `intake_port_flow` | function (lift→flow curve) | empty |
| `exhaust_port_flow` | function (lift→flow curve) | empty |
| `chamber_volume` | volume | `118 cc` |
| `intake_runner_volume` | volume | `300 cc` |
| `intake_runner_cross_section_area` | area | `circle_area(0.75 in)` |
| `exhaust_runner_volume` | volume | `300 cc` |
| `exhaust_runner_cross_section_area` | area | `circle_area(0.85 in)` |
| `flip_display` | bool | `false` (mirrors second bank) |

A head also requires a **valvetrain** — see §10.

Port flow curves are built with `function(filter_radius).add_flow_sample(lift,
flow)` samples (see `07_gm_ls.mr:33-57` for the canonical pattern).

**UI suggestion:** expose port flow as either a graphical editor or a
"flow scale" + preset curves (mirrors the `flow_attenuation` / `lift_scale`
trick used in the LS head builder).

---

## 10. Valvetrain

Two implementations — choose one per head:

**`standard_valvetrain`** (`objects.mr:341`)
- `intake_camshaft`
- `exhaust_camshaft`

**`vtec_valvetrain`** (`objects.mr:347`) — two-stage cams.
- `intake_camshaft`, `exhaust_camshaft` (low cam)
- `vtec_intake_camshaft`, `vtec_exhaust_camshaft` (high cam)
- `min_rpm` (default `5800 rpm`)
- `min_speed` (default `10 mph`)
- `manifold_vacuum` (default `1 atm − 5 inHg`)
- `min_throttle_position` (default `0.3`)

---

## 11. Camshaft (`camshaft_parameters`)

`objects.mr:457`.

| Field | Units |
|---|---|
| `advance` | angle (cam advance/retard from baseline) |
| `base_radius` | length (typically `0.5–1.0 in`) |
| `lobe_profile` | function (lift curve, see below) |

Lobes are added with `.add_lobe(centerline_angle)` per cylinder. Cam
*centerlines* per cylinder are derived from firing order × bank — the UI
should not require manual entry; generate them automatically.

### Lobe profile generation

`harmonic_cam_lobe` (`actions.mr:202`) generates the lift curve:

| Field | Units | Default |
|---|---|---|
| `duration_at_50_thou` | angle | `0` |
| `gamma` | float | `1.0` (curve sharpness) |
| `lift` | length | `300 thou` |
| `steps` | int | `100` (resolution) |

Plus per-cam:
- `lobe_separation` (angle, default `114°`)
- `intake_lobe_center`, `exhaust_lobe_center` (default = lobe_separation)

**UI suggestion:** "Cam builder" form with duration @ 50 thou, max lift,
lobe separation, intake/exhaust centerlines, advance. Hide `gamma`/`steps`
behind an advanced toggle. Optionally, a "cam preset" selector pulling from
`es/part-library/parts/camshafts.mr` (e.g. `chevy_454_stock_camshaft`,
`comp_cams_magnum_11_450_8`).

---

## 12. Intake (`intake_parameters`)

`objects.mr:484`.

| Field | Units | Default |
|---|---|---|
| `plenum_volume` | volume | `2.0 L` |
| `plenum_cross_section_area` | area | `100 cm²` |
| `intake_flow_rate` | flow (`k_carb(cfm)`) | `0` |
| `idle_flow_rate` | flow | `0` |
| `molecular_afr` | float | `12.5` |
| `idle_throttle_plate_position` | float (0–1) | `0.975` |
| `throttle_gamma` | float | `2.0` |
| `runner_length` | length | `4 in` |
| `runner_flow_rate` | flow (`k_carb`) | `k_carb(200)` |
| `velocity_decay` | float | `0.25` |

**UI suggestion:** intake CFM ("carburetor size") is the most user-facing
knob; the `chevy_bbc_stock_intake` / `performer_rpm_intake` helpers in
`part-library/parts/intakes.mr` show the simplified preset form (cfm,
idle_cfm, idle_throttle_position, throttle_gamma).

---

## 13. Exhaust System (`exhaust_system_parameters`)

`objects.mr:545`. One or more per engine (e.g. one per bank).

| Field | Units | Default |
|---|---|---|
| `volume` | volume | `100 L` |
| `length` | length | `volume / collector_cross_section_area` |
| `collector_cross_section_area` | area | `circle_area(2 in)` |
| `outlet_flow_rate` | flow | `k_carb(1000)` |
| `primary_tube_length` | length | `10 in` |
| `primary_flow_rate` | flow | `k_carb(100)` |
| `audio_volume` | float | `1.0` |
| `velocity_decay` | float | `1.0` |
| `impulse_response` | impulse_response | required for audio |

`impulse_response` (`objects.mr:539`): `{ filename: string, volume: float }`.
The library exposes prebuilt IRs via `impulse_response_library ir_lib()`
— UI should let the user pick from that list rather than typing filenames.

---

## 14. Ignition Module (`ignition_module`)

`objects.mr:592`.

| Field | Units | Default |
|---|---|---|
| `timing_curve` | function (RPM→advance) | required |
| `rev_limit` | RPM | `7000 rpm` |
| `limiter_duration` | seconds | `0.5 s` |

Wires (`ignition_wire`) are connected with `.connect_wire(wire, angle)` in
firing order. The angle defines when in the 720° cycle that cylinder fires.

**UI suggestion:** expose the timing curve as a graph editor (mirror what the
existing simulator already does internally). Firing order should be picked
from a dropdown matched to bank/cylinder count, and the connect_wire angles
auto-generated.

---

## 15. Vehicle (`vehicle`)

`objects.mr:603`. Wired with `set_vehicle(...)`.

| Field | Units | Default |
|---|---|---|
| `mass` | mass | `1000 kg` |
| `drag_coefficient` | float | `0.25` |
| `cross_sectional_area` | area | `(72 in) × (72 in)` |
| `diff_ratio` | float | `3.42` |
| `tire_radius` | length | `10 in` |
| `rolling_resistance` | force | `2000` |

Confirmed by `Vehicle::Parameters` in `vehicle.h:8`.

---

## 16. Transmission (`transmission`)

`objects.mr:614`. Wired with `set_transmission(...)`.

| Field | Units | Default |
|---|---|---|
| `max_clutch_torque` | torque | `1000 lb-ft` |

Gears are added with `.add_gear(ratio)` (`actions.mr:228`). Order matters —
first gear added is gear 1. Reference: `07_gm_ls.mr:438` shows a Corvette
6-speed: `2.97 / 2.07 / 1.43 / 1.00 / 0.71 / 0.57`.

Confirmed by `Transmission::Parameters` in `transmission.h:10`: only
`GearCount`, `GearRatios[]`, and `MaxClutchTorque` are read by the C++ side.

> **Important:** the simulator's transmission model is intentionally minimal —
> *no* reverse gear, *no* synchros, *no* shift time, *no* final drive
> separate from the vehicle's `diff_ratio`. Do not surface options the
> backend cannot consume.

**UI for transmission build:** a single number input for clutch torque + a
reorderable list of gear ratios. Number of gears is implicit in the list
length.

---

## 17. Reusable Helpers Worth Exposing

These are not separate objects, but the build UI should use them so values
match what the reference engines produce:

- `circle_area(radius)` — for runner / collector areas.
- `k_carb(cfm)` and `k_28inH2O(flow)` — flow coefficient constructors.
- `rod_moment_of_inertia(mass, length)` — connecting rod inertia.
- `disk_moment_of_inertia(mass, radius)` — crank / flywheel inertia.
- `harmonic_cam_lobe(...)` — cam lift profile generator.

---

## 18. Suggested UI Scope (Minimum Viable Build)

A first-pass "new engine" form can ship with a small subset and still
produce a working engine:

**Required:**
- Engine name, redline.
- Layout: bank count, bank angle, cylinder count, firing order.
- Bore, stroke, rod length, compression height.
- Piston mass, rod mass, crank mass, flywheel mass + radius.
- Cam: duration @ 50 thou, lift, lobe separation, intake/exhaust centerline, advance.
- Head: chamber volume, intake/exhaust runner volume + area, port flow scale.
- Intake: plenum volume, CFM, idle CFM, idle throttle position.
- Exhaust: collector area, primary length, audio volume, IR selection.
- Ignition: timing curve (graph editor), rev limit.
- Fuel: preset selector.

**Transmission:**
- Max clutch torque.
- Ordered list of gear ratios.

**Vehicle:**
- Mass, drag coefficient, frontal area, diff ratio, tire radius, rolling
  resistance.

Everything else (governor mode, VTEC, slave rods/radial geometry, full
graphical curve editors for fuel + port flow + cam lift) belongs in an
"advanced" tab.
