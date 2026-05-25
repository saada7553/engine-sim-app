#ifndef ATG_ENGINE_SIM_THERMAL_SYSTEM_H
#define ATG_ENGINE_SIM_THERMAL_SYSTEM_H

#include "units.h"

#include <mutex>
#include <random>
#include <vector>

class Engine;

// Tier-3 thermal + damage simulation.
//
// Embedded on Engine like IgnitionModule. Owns per-cylinder wall temperatures,
// global coolant/oil thermals, per-component health values, and queues audio
// events (knock, misfire, bent-valve clack, etc.) to be consumed by the
// synthesizer mix path. All public accessors are thread-safe via a single
// mutex — accesses are infrequent enough that lock contention is a non-issue.
//
// Damage and thermals are session-only — repairAll() restores everything to
// pristine; engine swap re-initializes via the Engine constructor path.
class ThermalSystem {
    public:
        // 0.0 = destroyed, 1.0 = pristine.
        struct CylinderComponents {
            double headGasket   = 1.0;
            double pistonRings  = 1.0;
            double piston       = 1.0;
            double rod          = 1.0;
            double rodBearing   = 1.0;
            double intakeValve  = 1.0;
            double exhaustValve = 1.0;
        };

        struct EngineWideComponents {
            double cylinderHead  = 1.0;
            double camshaft      = 1.0;
            double crankshaft    = 1.0;
            double mainBearing   = 1.0;
            double waterPump     = 1.0;
            double oilPump       = 1.0;
        };

        // Identifies components for the bridge layer's per-component query.
        // Must stay in sync with the EngineComponentId enum in EngineWrapper.h.
        enum class ComponentId {
            // Per-cylinder
            HeadGasket, PistonRings, Piston, Rod, RodBearing,
            IntakeValve, ExhaustValve,
            // Engine-wide
            CylinderHead, Camshaft, Crankshaft, MainBearing,
            WaterPump, OilPump
        };

    public:
        ThermalSystem();
        ~ThermalSystem() = default;

        // Allocates per-cylinder vectors and resets all health/thermals to
        // pristine. Engine pointer is retained for read-only queries during
        // tick (e.g., reading chamber peak pressures).
        void initialize(int cylinderCount, const Engine *engine);

        // Called once per physics step (from PistonEngineSimulator::simulateStep_),
        // before the fluid loop. Drives heat flow, oil model, damage
        // accumulation, audio event evaluation. throttlePosition and
        // clutchPressure are needed for moneyshift detection.
        void update(double dt,
                    double rpm,
                    double redline,
                    double revLimitRpm,
                    double throttlePosition,
                    double clutchPressure,
                    double vehicleSpeedMps);

        // Restore everything to pristine. Coolant 90°C, oil 80°C, full health.
        void repairAll();

        // Master damage switch ("drive freely" mode). When disabled, no
        // mechanical wear accrues, moneyshift / over-rev / knock damage is
        // suppressed, and any existing damage is healed each tick so the engine
        // stays pristine no matter how it's abused. Heat and oil still model
        // normally so the temperature gauges keep working.
        void setDamageEnabled(bool enabled);
        bool isDamageEnabled() const;

        // ----- Pump controls (user-facing) -----
        void setCoolantPumpEnabled(bool enabled);
        void setOilPumpEnabled(bool enabled);
        bool isCoolantPumpEnabled() const;
        bool isOilPumpEnabled() const;

        // ----- Live thermal readouts (thread-safe) -----
        double getCoolantTempC() const;
        double getOilTempC() const;
        double getOilPressurePsi() const;
        double getCylinderWallTempC(int cylinderIndex) const;
        double getCylinderWallTempK(int cylinderIndex) const;  // hot path: avoids C↔K convert

        // ----- Damage readouts (thread-safe) -----
        CylinderComponents getCylinderComponents(int cylinderIndex) const;
        EngineWideComponents getEngineWideComponents() const;
        // min over the 7 per-cylinder components of cylinder i.
        double getCylinderAggregateHealth(int cylinderIndex) const;
        double getTopEndHealth() const;     // head, cam, valves (avg)
        double getMidHealth() const;        // gaskets, rings, pistons (avg)
        double getBottomEndHealth() const;  // rods, bearings, crank, mains (avg)
        bool isCylinderSeized(int cylinderIndex) const;
        // "Dead" = catastrophically failed (rod ejected, valve dropped, etc.)
        // The cylinder produces no compression, no combustion, no exhaust
        // pulse, and contributes no mechanical noise of its own — it's just
        // an empty hole moving with the crank.
        bool isCylinderDead(int cylinderIndex) const;
        // Engine is permanently seized — won't spin under any starter torque.
        bool isEngineSeized() const;
        // Single-component query for the bridge.
        double getComponentHealth(int cylinderIndex, ComponentId component) const;

        // Hard-kill multiplier: 0 if seized, 1 otherwise. Damaged-but-not-
        // seized cylinders still see force because their reduced combustion
        // pressure (via sampleCombustionEfficiency) already cuts power.
        double getSeizureForceMultiplier(int cylinderIndex) const;

        // ----- Combustion-physics hooks (called per firing event) -----
        // True if this ignition event should misfire (skip combustion).
        // Probability rises with damage; seized cylinders always misfire.
        // RNG-driven, call exactly once per firing decision.
        bool shouldMisfire(int cylinderIndex);
        // 0..1 multiplier applied to flame efficiency in CombustionChamber::
        // ignite. Includes per-cycle variance so each firing of a damaged
        // cylinder sounds different — natural rough-running texture.
        double sampleCombustionEfficiency(int cylinderIndex);
        // >= 1.0 scalar applied to blowby coefficient in CombustionChamber::
        // flow. A blown gasket leaks compression through the rings.
        double getBlowbyMultiplier(int cylinderIndex) const;
        // J of energy to inject into the chamber gas mid-cycle to simulate a
        // detonation pressure spike. Returns 0 most of the time.
        double sampleKnockImpulse(int cylinderIndex);
        // J of energy to inject into the exhaust runner gas system when a
        // misfire is consumed — unburned fuel "pop" exiting the chamber.
        double sampleMisfireBackfire(int cylinderIndex);

        // ----- Continuous damage state (rotation-driven audio path) -----
        // These are not consumed events — they describe the engine's CURRENT
        // state and are queried each audio sample. The caller decides when
        // mechanical events fire (e.g. on TDC crank-angle crossings) and uses
        // these amplitudes to scale them.
        //
        // 0..1 amplitude for rod knock — how loud each rod slap will be when
        // its bearing journal contacts the rod. Driven by main bearing, rod,
        // and per-cyl rod-bearing health.
        double getRodKnockLevel(int cylinderIndex) const;
        // 0..1 amplitude for piston slap — piston rocking in the bore at
        // velocity reversals. Driven by piston health.
        double getPistonSlapLevel(int cylinderIndex) const;
        // 0..1 amplitude for valve clatter — bent or worn valves clicking
        // on their seats at every valve event. Driven by valve health.
        double getValveClatterLevel(int cylinderIndex) const;
        // 0..1 continuous bearing-whine level. Mixed at frequency proportional
        // to RPM by the caller.
        double getBearingWhineLevel() const;
        // 0..1 continuous block-hum level. Mixed as low-frequency rumble.
        double getBlockHumLevel() const;

        // Progressive rotational DRAG from worn bearings (oil starvation). 0 at
        // healthy/lightly-worn, rising as bearings wipe — the engine has to fight
        // this friction, so revs sag before catastrophic failure. Includes a
        // random per-engine strength so how hard the revs drop varies each run.
        double getBearingDragFactor() const;

        // ----- Hooks from CombustionChamber (called inside physics step) -----
        // Wall heat exchange: chamber subtracts Q from its gas; symmetric Q
        // is added to the cylinder wall here.
        void accumulateWallHeat(int cylinderIndex, double joules);

        // ----- One-shot event flags (consumed by audio mix) -----
        bool popBentValveEvent(int cylinderIndex);
        bool popMoneyshiftEvent();
        // Severity (over-redline excess, ~0..N) captured the instant the most
        // recent catastrophic moneyshift fired. Read alongside popMoneyshiftEvent
        // so the UI can scale the strength of the crash haptic to the over-rev.
        double lastMoneyshiftSeverity() const { return m_lastMoneyshiftSeverity; }
        // Catastrophic failure — rod ejection, valve drop, severe seizure.
        // Triggered automatically when damage thresholds are crossed. The
        // audio mix consumes this and fires a big BANG.
        bool popCatastrophicEvent();

        // TEST ONLY: force a catastrophic failure now (for offline audio capture).
        void debugForceCatastrophe();

        // Tracks how many of each failure type happened during the last
        // catastrophic event. Audio mix reads this to bias its BANG sound
        // toward the matching resonators — valves-only event sounds
        // metallic, rods-only event sounds deep, etc.
        struct FailureCounts {
            int rods    = 0;
            int valves  = 0;
            int gaskets = 0;
            int pistons = 0;
            bool cam    = false;
            bool crank  = false;
            bool oilPump = false;
        };
        FailureCounts popCatastropheCounts();

    private:
        // Internal step helpers (called from update under write lock).
        void tickHeatFlow(double dt, double vehicleSpeedMps, double combustionLoad);
        void tickOilModel(double dt, double rpm, double vehicleSpeedMps, double revFraction);
        void tickDamage(double dt, double rpm, double redline, double revLimitRpm);
        void detectMoneyshift(double dt, double rpm, double revLimitRpm,
                              double throttle, double clutchPressure);
        void applyMoneyshiftDamage(double rpm, double redline);
        void evaluateValveFloat(double dt, double rpm, double revLimitRpm);
        void clampAllHealth();
        // Heal all health/damage/event state back to pristine WITHOUT touching
        // thermals. Used both by repairAll and, every tick, by the damage-off
        // mode. Caller must hold m_lock.
        void resetHealthLocked();
        double aggregateHealthLocked(int cylinderIndex) const;
        // Roll probabilistic failure modes for a catastrophic event. Each
        // cylinder independently rolls for rod-ejection / valve-drop / gasket-
        // blow / cracked-piston; engine-wide rolls for cam-snap, crank-break,
        // oil-pump-fail. Different events produce different patterns.
        // Caller must hold m_lock.
        void rollAndApplyCatastrophicFailures(double severity);
        // Weighted-random rod ejection: picks a random alive cylinder weighted
        // by its current rod damage. Caller must hold m_lock.
        void triggerRodEjection();
        // Mark a specific cylinder dead + damage main bearing. Used by both
        // probabilistic moneyshift rolls and oil-starvation events.
        void killCylinderById(int cylinderIndex);

    private:
        mutable std::mutex m_lock;
        const Engine *m_engine = nullptr;
        int m_cylinderCount = 0;

        // Health state.
        std::vector<CylinderComponents> m_cylinders;
        EngineWideComponents m_engineWide;

        // Thermal state (SI: K, Pa).
        double m_coolantTempK = units::celcius(90.0);
        double m_oilTempK     = units::celcius(80.0);
        double m_oilPressurePa = 0.0;
        std::vector<double> m_wallTempK;

        // Pump state.
        bool m_coolantPumpEnabled = true;
        bool m_oilPumpEnabled     = true;

        // Master damage switch — see setDamageEnabled().
        bool m_damageEnabled = true;

        // One-shot audio events.
        std::vector<bool> m_bentValvePending;
        bool m_moneyshiftPending = false;
        bool m_catastrophicPending = false;
        FailureCounts m_lastCatastropheCounts;
        // Per-cylinder "dead" state: catastrophically failed, doesn't fire
        // and doesn't make mechanical noise. Engine still spins on remaining
        // cylinders unless the engine itself is seized.
        std::vector<bool> m_cylinderDead;
        // Whole-engine seizure: the crank cannot turn.
        bool m_engineSeized = false;
        // Sustained moneyshift severity tracker — used to detect when the
        // over-rev becomes catastrophic (versus just damaging).
        double m_moneyshiftSeverityIntegral = 0.0;
        // One-shot: true once a catastrophic moneyshift has fired this
        // event. Resets when the engine returns to normal operating range.
        // Prevents repeated rod-ejection cascades during a single over-rev,
        // which sounded like Geiger-counter clicks.
        bool m_moneyshiftHasFired = false;
        // Over-rev severity captured at the moment the catastrophe fired (see
        // lastMoneyshiftSeverity). Drives crash-haptic strength on the UI side.
        double m_lastMoneyshiftSeverity = 0.0;

        // Moneyshift detection state.
        double m_lastRpm           = 0.0;
        double m_moneyshiftCooldown = 0.0;  // seconds remaining

        // Random per-engine multiplier on bearing-wear drag — randomizes how
        // hard revs sag as oil-starved bearings wipe (set in initialize()).
        double m_bearingDragRandom = 1.0;

        // RNG for valve float (small-state Mersenne).
        std::mt19937 m_rng{0xE5E5E5E5u};
        std::uniform_real_distribution<double> m_unit{0.0, 1.0};
};

#endif /* ATG_ENGINE_SIM_THERMAL_SYSTEM_H */
