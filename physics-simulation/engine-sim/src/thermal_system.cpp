#include "../include/thermal_system.h"

#include "../include/engine.h"

#include <algorithm>

namespace {
    // -------- Thermal model constants --------
    constexpr double kAmbientK            = units::celcius(25.0);
    constexpr double kNominalCoolantK     = units::celcius(90.0);
    constexpr double kNominalOilK         = units::celcius(80.0);
    constexpr double kInitialWallK        = units::celcius(90.0);

    // Per-cylinder wall thermal mass. Smaller than reality so walls respond
    // in seconds, not minutes — matches game timescales.
    constexpr double kWallThermalMassJK   = 700.0;
    // Coolant thermal mass. Compressed vs reality so the engine warms up and —
    // critically — OVERHEATS on a game timescale: with the pump off, coolant
    // should visibly climb into the red within ~half a minute of driving, not
    // creep up over several minutes. Only changes response RATE, not the
    // equilibrium temperatures (those are set by the heat-in/heat-out balance).
    constexpr double kCoolantThermalMassJK = 3000.0;
    constexpr double kOilThermalMassJK    = 2500.0;

    // Wall-to-coolant heat coupling (W/K per cylinder). This carries the local
    // wall heat into the coolant, but it's a secondary path — the bulk of the
    // coolant heat comes from the normalized combustion-rejection term below.
    constexpr double kWallCoolantCouplingOn  = 24.0;
    // With pump off, coolant doesn't flow but it still conducts (stagnant
    // water in contact with cylinder walls). 30% of full flow is realistic
    // for stalled coolant; the actual heat trap is the radiator going cold.
    constexpr double kWallCoolantCouplingOff = 7.0;

    // ---- Engine-normalized heat balance ----
    // Both heat generation and cooling capacity scale with cylinder count
    // (engine size) and with engine speed expressed as a FRACTION of redline,
    // so a 1.0L economy engine and a 15,000-rpm race engine settle at the same
    // operating temperatures and neither one runs away. This is why fixed
    // danger thresholds work across every engine type: each engine regulates
    // into the same band rather than to an absolute rpm/displacement.
    //
    // Combustion heat into coolant scales ~linearly with load (airflow). At
    // full load (redline + WOT) each cylinder rejects this many watts.
    constexpr double kCoolantHeatPerCylWAtFullLoad = 3000.0;
    // Bearing-friction heat into oil scales with the SQUARE of rev fraction
    // (friction torque itself climbs with rpm). At redline, watts per cylinder.
    constexpr double kOilFrictionPerCylWAtRedline  = 900.0;
    // Even at closed throttle the engine burns some fuel, so combustion heat
    // never drops fully to zero (coolant stays warm on the overrun).
    constexpr double kCombustionIdleLoadFloor      = 0.05;

    // Cooling capacity (W/K). Per-cylinder terms scale with engine size; speed
    // terms add radiator/cooler airflow. Sized so full-load equilibrium lands
    // in the normal band (coolant ~95-100°C, oil ~100-105°C) for any engine.
    constexpr double kRadiatorPerCylCoupling   = 42.0;
    constexpr double kRadiatorSpeedCoupling    = 3.0;   // per (m/s) — kept SMALL vs the per-cyl term so coolant tracks LOAD (hard driving = warmer), not airflow (which used to make speed COOL the engine and lifting off warm it)
    constexpr double kOilCoolerPerCylCoupling  = 12.0;
    constexpr double kOilCoolerSpeedCoupling   = 0.8;   // per (m/s)
    // Oil <-> cylinder-wall splash/spray coupling (W/K, pump-independent).
    constexpr double kOilWallCoupling          = 4.0;

    // Coolant + oil thermostats: cooling is bypassed until each fluid is up to
    // temperature, then ramps fully open over a narrow band. Without this the
    // speed-scaled radiator would drag coolant toward ambient — cruising fast
    // would COOL the engine below 90°C instead of holding it there.
    constexpr double kThermostatOpenC           = 87.0;
    constexpr double kThermostatFullOpenC       = 100.0;
    constexpr double kOilThermostatOpenC        = 85.0;
    constexpr double kOilThermostatFullOpenC    = 105.0;

    // Block surface convection to ambient (W/K per cylinder). With the pump off
    // and the radiator dead, this bare-metal-to-still-air path is the ONLY way
    // heat escapes. Nothing about idle is special-cased — behaviour falls out of
    // the heat balance: equilibrium coolant temp = ambient + combustionHeat/this.
    // It's sized so that LIGHT idle combustion heat balances near normal temp
    // (~88°C → idle holds, and an already-overheated engine COOLS back down when
    // you drop to idle), while any real driving load swamps it and overheats.
    // (Too high → pump-off does nothing even under load; too low → idle cooks,
    // which isn't physical.) Per-cylinder so it scales with engine size.
    constexpr double kBlockPassiveConvectionPerCyl = 3.0;

    // Oil pressure curve (psi as a function of RPM).
    constexpr double kOilPsiAtIdle       = 25.0;
    constexpr double kOilPsiPerRpm       = 0.025;   // ramps to ~70 psi by 3000 rpm
    constexpr double kOilPsiMax          = 70.0;
    constexpr double kIdleRpm            = 1000.0;

    // -------- Damage rules tuning --------
    // Engines don't wear from "operation"; they wear from ABUSE. Normal
    // driving — even hard driving on a high-performance engine — should
    // produce ZERO damage. Damage only accumulates when something is
    // genuinely wrong: cooling system failed, oil pump off, sustained
    // over-rev, real detonation, or moneyshift.
    //
    // All wall-temperature damage is removed — wall temps naturally run
    // 200-400°C in normal operation; using them as damage thresholds means
    // every engine slowly dies during normal driving. Heat damage hangs on
    // COOLANT temperature instead — when coolant overheats, the engine is
    // genuinely in trouble.
    constexpr double kHeadOverheatThreshC        = 115.0;  // coolant temp
    // Overheat POWER derate — a FELT effect, not just slow damage. An overheating
    // engine loses power (heat soak cuts volumetric efficiency, the ECU retards
    // timing / pulls fuel to fight detonation, and ultimately coolant boils). So
    // when coolant runs hot, combustion efficiency ramps down: the engine goes
    // sluggish well before the head gasket lets go, which is the immediate cue
    // that the cooling system has failed. Normal operation (~90°C) is untouched.
    constexpr double kThermalDerateStartC        = 108.0;  // power starts dropping here
    constexpr double kThermalDeratePerC          = 0.012;  // fraction lost per °C over start
    constexpr double kThermalDerateFloor         = 0.35;   // limps, never fully dies from heat alone
    // Damage rates set so a coolant-pump-off overheat does visible harm within
    // ~1 minute, not several. With the pump off the coolant climbs fast (see
    // kBlockPassiveConvectionPerCyl), and once it's ~40°C over threshold the
    // head gasket fails in well under a minute.
    constexpr double kHeadGasketDamagePerCDt     = 5.0e-4;
    constexpr double kHeadDamagePerCDt           = 3.0e-4;
    // Knock damage requires very high pressure AND very high temp together.
    // Modern engines routinely peak 100-150 bar with peaks of 2000-2300K
    // in normal operation. Real knock is 180+ bar AND 2600+K simultaneously.
    constexpr double kKnockPeakPa                = 19.0e6;  // 190 bar
    constexpr double kKnockTempK                 = 2600.0;
    constexpr double kDetonationPeakPa           = 22.0e6;  // 220 bar
    constexpr double kDetonationPeakK            = 2700.0;
    constexpr double kKnockRingDamage            = 0.0008;  // per knock event
    // Over-rev damage uses ENGINE-RELATIVE thresholds (redline ratios) so
    // the same rule works for an economy car and a 10k-redline race engine.
    constexpr double kRodOverRevThreshRatio      = 1.15;
    constexpr double kRodOverRevDamageCoeff      = 3.0e-3;
    // Oil starvation: bearings ride on a pressurized oil film, so losing oil
    // pressure while the engine is turning wipes them out FAST — at any running
    // speed, not just high rpm (the old 3500-rpm gate let you drive forever on
    // a dead oil pump). Below the film-pressure threshold, damage scales with
    // how far pressure has collapsed and with rpm.
    constexpr double kOilStarveRunningRpm        = 600.0;   // engine is turning
    constexpr double kOilStarveFilmPsi           = 12.0;    // film breaks below this (normal idle ~25)
    constexpr double kRodStarveDamageRate        = 0.05;    // ~15-40s to wipe a bearing at zero psi
    constexpr double kCamStarveDamageRate        = 0.015;
    constexpr double kCrankOverRevRatio          = 1.25;
    constexpr double kCrankOverRevDamageCoeff    = 1.5e-2;
    constexpr double kWaterPumpHeatThreshC       = 125.0;
    constexpr double kWaterPumpDamagePerCDt      = 5.0e-5;
    constexpr double kOilPumpOverRevRatio        = 1.20;
    constexpr double kOilPumpOverRevDamageCoeff  = 7.0e-4;
    // Exhaust valve damage hangs on coolant temp now (overall engine heat),
    // not wall temp. Only fires during real overheat events.
    constexpr double kExhaustValveOverheatC      = 125.0;
    constexpr double kExhaustValveDamagePerCDt   = 8.0e-5;

    // Moneyshift detection.
    constexpr double kMoneyshiftThrottleClosed    = 0.15;
    constexpr double kMoneyshiftClutchEngaged     = 0.50;
    constexpr double kMoneyshiftRpmRiseRate       = 8000.0;  // rpm/s
    constexpr double kMoneyshiftRedlineRatio      = 0.95;
    constexpr double kMoneyshiftCooldownSec       = 0.50;
    constexpr double kMoneyshiftRodDamageCoeff    = 0.15;
    constexpr double kMoneyshiftBearingDamageCoeff = 0.08;
    constexpr double kMoneyshiftCrankDamageCoeff  = 0.05;

    // Valve float.
    constexpr double kValveFloatRatioThresh   = 1.10;
    constexpr double kValveFloatProbCoeff     = 2.0;   // saturates at 0.5/s above 1.35
    constexpr double kValveFloatDamage        = 0.20;

    // Seizure thresholds.
    constexpr double kSeizureRingThresh        = 0.02;
    constexpr double kSeizureRodBearingThresh  = 0.05;
    constexpr double kSeizureMainBearingThresh = 0.05;

    // Audio thresholds.
    constexpr double kRodKnockMainBearingThresh = 0.50;
    constexpr double kRodKnockRodBearingThresh  = 0.30;
    constexpr double kRodKnockRodThresh         = 0.40;
    constexpr double kBearingWhineMainThresh    = 0.60;
    constexpr double kBearingWhineRpm           = 3000.0;

    inline double clamp01(double x) {
        return std::max(0.0, std::min(1.0, x));
    }

    inline double celcius(double k) {
        // K → °C, mirroring units::celcius which goes the other way.
        return (k - units::celcius(0.0));
    }

    // Deadzone curve: returns 0 below the threshold, then ramps cubically to 1
    // at fully destroyed. Real engines stay silent until wear becomes audible —
    // a 10%-worn bearing sounds the same as a new one.
    inline double audioDeadzone(double damage, double thresh) {
        if (damage <= thresh) return 0.0;
        const double t = (damage - thresh) / (1.0 - thresh);
        return t * t * t;
    }
}

ThermalSystem::ThermalSystem() = default;

void ThermalSystem::initialize(int cylinderCount, const Engine *engine) {
    std::lock_guard<std::mutex> lock(m_lock);
    m_engine = engine;
    m_cylinderCount = cylinderCount;
    m_cylinders.assign(cylinderCount, CylinderComponents{});
    m_engineWide = EngineWideComponents{};
    m_coolantTempK = kNominalCoolantK;
    m_oilTempK = kNominalOilK;
    m_oilPressurePa = 0.0;
    m_wallTempK.assign(cylinderCount, kInitialWallK);
    m_peakPressurePa.assign(cylinderCount, 0.0);
    m_peakTempK.assign(cylinderCount, 0.0);
    m_bentValvePending.assign(cylinderCount, false);
    m_knockArmed.assign(cylinderCount, false);
    m_cylinderDead.assign(cylinderCount, false);
    m_coolantPumpEnabled = true;
    m_oilPumpEnabled = true;
    m_moneyshiftPending = false;
    m_catastrophicPending = false;
    m_engineSeized = false;
    m_lastRpm = 0.0;
    m_moneyshiftCooldown = 0.0;
    m_moneyshiftSeverityIntegral = 0.0;
    m_moneyshiftHasFired = false;
    // Randomize how hard the revs sag from bearing-wear drag this run.
    m_bearingDragRandom = 0.6 + m_unit(m_rng) * 1.1;   // 0.6 - 1.7
}

void ThermalSystem::repairAll() {
    std::lock_guard<std::mutex> lock(m_lock);
    resetHealthLocked();
    m_coolantTempK = kNominalCoolantK;
    m_oilTempK = kNominalOilK;
    m_oilPressurePa = 0.0;
    std::fill(m_wallTempK.begin(), m_wallTempK.end(), kInitialWallK);
    std::fill(m_peakPressurePa.begin(), m_peakPressurePa.end(), 0.0);
    std::fill(m_peakTempK.begin(), m_peakTempK.end(), 0.0);
    // Randomize how hard the revs sag from bearing-wear drag this run.
    m_bearingDragRandom = 0.6 + m_unit(m_rng) * 1.1;   // 0.6 - 1.7
}

// Heal health/damage/event state to pristine (no thermals). Caller holds lock.
void ThermalSystem::resetHealthLocked() {
    for (auto &c : m_cylinders) c = CylinderComponents{};
    m_engineWide = EngineWideComponents{};
    std::fill(m_bentValvePending.begin(), m_bentValvePending.end(), false);
    std::fill(m_knockArmed.begin(), m_knockArmed.end(), false);
    std::fill(m_cylinderDead.begin(), m_cylinderDead.end(), false);
    m_moneyshiftPending = false;
    m_catastrophicPending = false;
    m_engineSeized = false;
    m_moneyshiftCooldown = 0.0;
    m_moneyshiftSeverityIntegral = 0.0;
    m_moneyshiftHasFired = false;
}

void ThermalSystem::setDamageEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(m_lock);
    m_damageEnabled = enabled;
}

bool ThermalSystem::isDamageEnabled() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_damageEnabled;
}

// --------------------------------------------------------------------------
// Tick driver
// --------------------------------------------------------------------------

void ThermalSystem::update(double dt,
                           double rpm,
                           double redline,
                           double revLimitRpm,
                           double throttlePosition,
                           double clutchPressure,
                           double vehicleSpeedMps) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (m_cylinderCount == 0) return;

    // Normalize engine speed to a fraction of redline so the heat model behaves
    // the same on any engine. Combustion heat tracks airflow (rpm × throttle,
    // with an idle floor); friction heat tracks rev fraction squared.
    const double revFraction = (redline > 1.0) ? clamp01(rpm / redline) : 0.0;
    const double throttle01  = clamp01(throttlePosition);
    const double combustionLoad = revFraction
        * (kCombustionIdleLoadFloor + (1.0 - kCombustionIdleLoadFloor) * throttle01);

    tickHeatFlow(dt, vehicleSpeedMps, combustionLoad);
    tickOilModel(dt, rpm, vehicleSpeedMps, revFraction);

    if (m_damageEnabled) {
        detectMoneyshift(dt, rpm, revLimitRpm, throttlePosition, clutchPressure);
        tickDamage(dt, rpm, redline, revLimitRpm);
        evaluateValveFloat(dt, rpm, revLimitRpm);
        clampAllHealth();
    } else {
        // "Drive freely": keep the engine pristine and swallow any pending
        // crash/over-rev events so nothing breaks no matter how it's driven.
        resetHealthLocked();
    }

    if (m_moneyshiftCooldown > 0.0) m_moneyshiftCooldown -= dt;
    m_lastRpm = rpm;
}

void ThermalSystem::onCycleBoundary() {
    std::lock_guard<std::mutex> lock(m_lock);
    for (int i = 0; i < m_cylinderCount; ++i) {
        const double peakPa = m_peakPressurePa[i];
        const double peakK = m_peakTempK[i];

        // Knock damage requires BOTH high pressure AND high temperature —
        // either alone is just hard combustion, not knock. Real knock needs
        // end-gas auto-ignition, which only happens above ~2600K end-gas
        // temperatures. This protects high-performance engines that
        // routinely peak above 150 bar from accumulating phantom damage.
        if (m_damageEnabled && peakPa > kKnockPeakPa && peakK > kKnockTempK) {
            m_cylinders[i].pistonRings -= kKnockRingDamage;
        }
        if (m_damageEnabled && peakPa > kDetonationPeakPa && peakK > kDetonationPeakK) {
            const double over = (peakPa / kDetonationPeakPa) - 1.0;
            m_cylinders[i].piston -= 5.0e-4 * over;
        }

        m_knockArmed[i] = false;
        m_peakPressurePa[i] = 0.0;
        m_peakTempK[i] = 0.0;
    }
    for (auto &c : m_cylinders) {
        c.pistonRings = clamp01(c.pistonRings);
        c.piston = clamp01(c.piston);
    }
}

// --------------------------------------------------------------------------
// Heat flow
// --------------------------------------------------------------------------

void ThermalSystem::tickHeatFlow(double dt, double vehicleSpeedMps,
                                 double combustionLoad) {
    const double wallCoupling = m_coolantPumpEnabled
        ? kWallCoolantCouplingOn
        : kWallCoolantCouplingOff;

    // Wall ↔ coolant (per cylinder). Keeps wall temperatures bounded for the
    // gas-side heat exchange; a secondary contributor to coolant temperature.
    double totalQ_toCoolant = 0.0;
    for (int i = 0; i < m_cylinderCount; ++i) {
        const double dT = m_wallTempK[i] - m_coolantTempK;
        const double Q = dT * wallCoupling * dt;   // J leaving wall -> coolant
        m_wallTempK[i] -= Q / kWallThermalMassJK;
        totalQ_toCoolant += Q;
    }
    m_coolantTempK += totalQ_toCoolant / kCoolantThermalMassJK;

    // Primary coolant heat: combustion rejection, scaled by cylinder count and
    // load so every engine drives proportional heat into its coolant. This is
    // what actually pushes coolant up to operating temperature under load — the
    // wall path alone is too weak, which is why coolant used to only fall.
    const double Q_combustion =
        kCoolantHeatPerCylWAtFullLoad * m_cylinderCount * combustionLoad * dt;
    m_coolantTempK += Q_combustion / kCoolantThermalMassJK;

    // Coolant → ambient via radiator (pump-driven, thermostat-regulated).
    if (m_coolantPumpEnabled) {
        // Thermostat opening fraction: 0 below kThermostatOpenC (engine warms
        // up / holds temp), ramping to 1 by kThermostatFullOpenC. This caps how
        // hard the speed-scaled radiator can pull, so the engine settles around
        // operating temperature instead of being chilled toward ambient.
        const double coolantC = celcius(m_coolantTempK);
        const double thermostat = clamp01(
            (coolantC - kThermostatOpenC)
            / (kThermostatFullOpenC - kThermostatOpenC));
        const double radCoupling =
            (kRadiatorPerCylCoupling * m_cylinderCount
             + kRadiatorSpeedCoupling * vehicleSpeedMps)
            * m_engineWide.waterPump * thermostat;
        const double Q = (m_coolantTempK - kAmbientK) * radCoupling * dt;
        m_coolantTempK -= Q / kCoolantThermalMassJK;
    }
    // Pump off: only passive convection from the engine block to ambient.
    // No radiator flow, no fan — this is what makes the engine cook itself.
    else {
        const double Q = (m_coolantTempK - kAmbientK)
                       * kBlockPassiveConvectionPerCyl * m_cylinderCount * dt;
        m_coolantTempK -= Q / kCoolantThermalMassJK;
    }
}

void ThermalSystem::tickOilModel(double dt, double rpm, double vehicleSpeedMps,
                                 double revFraction) {
    // Heat in from bearing friction, normalized to redline so a high-revving
    // engine doesn't generate unbounded heat. Scales with rev fraction squared
    // (friction torque rises with rpm) and with cylinder count.
    const double Q_friction = kOilFrictionPerCylWAtRedline * m_cylinderCount
        * revFraction * revFraction * dt;  // J
    m_oilTempK += Q_friction / kOilThermalMassJK;

    // Heat in from a fraction of the average wall temp (oil touches the
    // bottom of the cylinder via splash + spray bars). Scales with wall temp
    // delta. Always present, doesn't depend on the oil pump.
    double avgWall = 0.0;
    for (double w : m_wallTempK) avgWall += w;
    avgWall /= std::max(1, m_cylinderCount);
    const double Q_fromWalls = (avgWall - m_oilTempK) * kOilWallCoupling * dt;
    m_oilTempK += Q_fromWalls / kOilThermalMassJK;

    // Heat out via cooler — only while the oil pump circulates oil through it,
    // gated by an oil thermostat (so oil reaches operating temperature instead
    // of being held cold at light load) and helped by airflow, and scaled by
    // engine size. With the pump off this entire escape path disappears, so the
    // oil climbs and — together with zero oil pressure — the engine is starved.
    if (m_oilPumpEnabled) {
        const double oilC = celcius(m_oilTempK);
        const double thermostat = clamp01(
            (oilC - kOilThermostatOpenC)
            / (kOilThermostatFullOpenC - kOilThermostatOpenC));
        const double coolerCoupling =
            (kOilCoolerPerCylCoupling * m_cylinderCount
             + kOilCoolerSpeedCoupling * vehicleSpeedMps)
            * m_engineWide.oilPump * thermostat;
        const double Q_cooler = (m_oilTempK - kAmbientK) * coolerCoupling * dt;
        m_oilTempK -= Q_cooler / kOilThermalMassJK;
    }

    // Oil pressure: f(rpm) × tempFactor × pumpHealth.
    if (m_oilPumpEnabled) {
        double psi;
        if (rpm < kIdleRpm) {
            psi = (rpm / kIdleRpm) * kOilPsiAtIdle;
        } else {
            psi = kOilPsiAtIdle + (rpm - kIdleRpm) * kOilPsiPerRpm;
        }
        psi = std::min(kOilPsiMax, std::max(0.0, psi));
        const double oilC = celcius(m_oilTempK);
        const double tempFactor = std::max(0.5, 1.0 - std::max(0.0, oilC - 90.0) * 0.005);
        psi *= tempFactor * m_engineWide.oilPump;
        m_oilPressurePa = psi * units::psi;
    } else {
        m_oilPressurePa = 0.0;
    }
}

// --------------------------------------------------------------------------
// Damage
// --------------------------------------------------------------------------

void ThermalSystem::tickDamage(double dt, double rpm, double redline, double revLimitRpm) {
    const double coolantC = celcius(m_coolantTempK);
    const double oilPsi = m_oilPressurePa / units::psi;
    // Over-rev damage is measured against the REV LIMITER, not the redline.
    // The engine can't exceed its limiter under its own power, so bouncing on
    // the limiter is safe; damage only accrues when the drivetrain forces the
    // engine past the limiter (money-shift / aggressive downshift). Measuring
    // against redline instead made normal high-rpm running — anywhere between
    // redline and the (higher) limiter — chew up valves and rods.
    const double rpmRatio = (revLimitRpm > 1.0) ? (rpm / revLimitRpm) : 0.0;

    // === Heat damage (engine-wide, driven by coolant temp) ===
    // The cooling system is what protects the engine from heat. When coolant
    // overheats — and ONLY when coolant overheats — heat damage accumulates.
    // Normal operation keeps coolant at ~90°C and produces zero heat damage,
    // regardless of how hot individual cylinder walls run.
    if (coolantC > kHeadOverheatThreshC) {
        const double over = coolantC - kHeadOverheatThreshC;
        // All cylinders' head gaskets degrade together — the gasket is one
        // piece of metal spanning the whole head.
        for (int i = 0; i < m_cylinderCount; ++i) {
            m_cylinders[i].headGasket -= over * kHeadGasketDamagePerCDt * dt;
        }
        m_engineWide.cylinderHead -= over * kHeadDamagePerCDt * dt;
    }
    if (coolantC > kExhaustValveOverheatC) {
        const double over = coolantC - kExhaustValveOverheatC;
        for (int i = 0; i < m_cylinderCount; ++i) {
            m_cylinders[i].exhaustValve -= over * kExhaustValveDamagePerCDt * dt;
        }
    }
    if (coolantC > kWaterPumpHeatThreshC) {
        m_engineWide.waterPump -=
            (coolantC - kWaterPumpHeatThreshC) * kWaterPumpDamagePerCDt * dt;
    }

    // === Oil starvation damage ===
    // Fires whenever oil pressure collapses below the film threshold while the
    // engine is turning — at ANY running speed, not just high rpm. At normal
    // pressure (idle ~25, cruise 40-70) this contributes nothing; with the oil
    // pump off (psi = 0) the bearings are wiped within seconds-to-tens-of-
    // seconds, faster the higher the rpm.
    if (rpm > kOilStarveRunningRpm && oilPsi < kOilStarveFilmPsi) {
        const double deficit = (kOilStarveFilmPsi - oilPsi) / kOilStarveFilmPsi; // 0..1
        const double rpmFactor = (redline > 1.0)
            ? (0.3 + 0.7 * clamp01(rpm / redline))
            : 0.5;
        const double rodRate = kRodStarveDamageRate * deficit * rpmFactor;
        for (int i = 0; i < m_cylinderCount; ++i) {
            m_cylinders[i].rodBearing -= rodRate * dt;
        }
        m_engineWide.mainBearing -= rodRate * dt;
        m_engineWide.camshaft    -= kCamStarveDamageRate * deficit * rpmFactor * dt;
    }

    // === Over-rev damage ===
    // Engine-relative — uses redline ratios so it works for any engine type.
    // An economy engine's redline is 6000; a race engine's is 10000; both
    // damage at the same RATIO (1.15× their own redline).
    if (rpmRatio > kRodOverRevThreshRatio) {
        const double over = rpmRatio - kRodOverRevThreshRatio;
        for (int i = 0; i < m_cylinderCount; ++i) {
            m_cylinders[i].rod -= over * over * kRodOverRevDamageCoeff * dt;
        }
    }
    if (rpmRatio > kCrankOverRevRatio) {
        const double over = rpmRatio - kCrankOverRevRatio;
        m_engineWide.crankshaft -= over * over * kCrankOverRevDamageCoeff * dt;
    }
    if (rpmRatio > kOilPumpOverRevRatio) {
        const double over = rpmRatio - kOilPumpOverRevRatio;
        m_engineWide.oilPump -= over * over * kOilPumpOverRevDamageCoeff * dt;
    }

    // Catastrophic oil starvation: when a rod bearing has been completely
    // chewed up AND the engine is still under load (above 1500 RPM), the
    // rod breaks loose and gets ejected. Same audio + state event as a
    // moneyshift catastrophe — different physical trigger.
    if (rpm > 1500.0) {
        for (int i = 0; i < m_cylinderCount; ++i) {
            if (m_cylinderDead[i]) continue;
            if (m_cylinders[i].rodBearing < 0.02
                || m_cylinders[i].rod        < 0.02) {
                triggerRodEjection();
                break;     // one event per step max
            }
        }
        if (m_engineWide.mainBearing < 0.02 && !m_engineSeized) {
            // Main bearing has failed completely — engine seizes.
            m_engineSeized = true;
            m_catastrophicPending = true;
        }
    }
}

void ThermalSystem::detectMoneyshift(double dt,
                                     double rpm,
                                     double revLimitRpm,
                                     double /*throttle*/,
                                     double clutchPressure) {
    if (dt <= 0.0 || revLimitRpm <= 1.0) return;

    // Throttle position is NOT in the gate: real moneyshifts often happen
    // with throttle still applied (driver downshifts mid-pull). The signature
    // of a moneyshift is "clutch engaged + RPM forced past the REV LIMITER" —
    // the engine can't exceed its limiter under its own power, so being past it
    // with the clutch engaged means the drivetrain is overspinning it. Measured
    // against redline instead, this fired during ordinary in-gear revving up to
    // the limiter (the limiter sits above redline) and bled rod health.
    const bool clutchEngaged  = clutchPressure > kMoneyshiftClutchEngaged;
    const double ratio = rpm / revLimitRpm;

    // Engine back in normal range — decay integral, allow re-fire when
    // RPM returns to safe territory.
    if (!clutchEngaged || ratio < 1.05) {
        m_moneyshiftSeverityIntegral *= std::max(0.0, 1.0 - dt * 2.0);
        if (ratio < 1.02) m_moneyshiftHasFired = false;
        return;
    }

    // Below the catastrophic threshold: mild continuous rod stress.
    const double excess = (ratio - 1.0) * (ratio - 1.0);
    if (ratio < 1.18) {
        for (int i = 0; i < m_cylinderCount; ++i) {
            m_cylinders[i].rod -= 0.6 * excess * dt;
        }
        m_engineWide.crankshaft -= 0.3 * excess * dt;
        return;
    }

    // === Catastrophic moneyshift ===
    // ONE discrete failure event. Parts break simultaneously. After firing,
    // lock out further events until RPM returns to safe range.
    const double catastrophicSeverity = std::max(0.0, ratio - 1.18);
    m_moneyshiftSeverityIntegral += catastrophicSeverity * dt;

    if (m_moneyshiftSeverityIntegral > 0.015 && !m_moneyshiftHasFired) {
        m_moneyshiftHasFired = true;
        m_moneyshiftPending  = true;
        m_lastMoneyshiftSeverity = catastrophicSeverity;
        rollAndApplyCatastrophicFailures(catastrophicSeverity);
    }
}

// Catastrophic moneyshift failure modes — rolled independently per event.
// Records which failure types happened in m_lastCatastropheCounts so the
// audio mix can bias its BANG sound toward the matching resonators.
void ThermalSystem::rollAndApplyCatastrophicFailures(double sev) {
    const double pRod    = std::min(0.55, sev * 0.50);
    const double pValve  = std::min(0.70, sev * 0.70);
    const double pGasket = std::min(0.55, sev * 0.55);
    const double pPiston = std::min(0.60, sev * sev * 0.85);
    const double pCam    = std::min(0.30, sev * 0.30);
    const double pCrank  = std::min(0.20, sev * sev * 0.25);
    const double pOilPump = std::min(0.20, sev * 0.20);

    // Reset counts for this event.
    FailureCounts counts;

    for (int i = 0; i < m_cylinderCount; ++i) {
        if (m_cylinderDead[i]) continue;
        auto &c = m_cylinders[i];

        if (m_unit(m_rng) < pRod) {
            killCylinderById(i);
            counts.rods++;
            continue;
        }
        if (m_unit(m_rng) < pValve) {
            c.intakeValve  = 0.0;
            c.exhaustValve = 0.0;
            counts.valves++;
        }
        if (m_unit(m_rng) < pGasket) {
            c.headGasket *= 0.15;
            counts.gaskets++;
        }
        if (m_unit(m_rng) < pPiston) {
            c.piston      *= 0.20;
            c.pistonRings *= 0.30;
            counts.pistons++;
        }
    }

    if (m_unit(m_rng) < pCam) {
        m_engineWide.camshaft *= 0.20;
        counts.cam = true;
    }
    if (m_unit(m_rng) < pCrank) {
        m_engineWide.crankshaft *= 0.10;
        m_engineSeized = true;
        counts.crank = true;
    }
    if (m_unit(m_rng) < pOilPump) {
        m_engineWide.oilPump *= 0.30;
        counts.oilPump = true;
    }

    // Make sure SOMETHING happened so we don't fire a silent BANG.
    if (counts.rods + counts.valves + counts.gaskets + counts.pistons == 0
        && !counts.cam && !counts.crank && !counts.oilPump) {
        // Force at least one minor failure so the catastrophe has audible
        // teeth. Pick a valve (most common real moneyshift outcome).
        for (int i = 0; i < m_cylinderCount; ++i) {
            if (m_cylinderDead[i]) continue;
            m_cylinders[i].intakeValve  *= 0.3;
            m_cylinders[i].exhaustValve *= 0.3;
            counts.valves = 1;
            break;
        }
    }

    m_lastCatastropheCounts = counts;
    m_catastrophicPending = true;
}

ThermalSystem::FailureCounts ThermalSystem::popCatastropheCounts() {
    std::lock_guard<std::mutex> lock(m_lock);
    const FailureCounts c = m_lastCatastropheCounts;
    m_lastCatastropheCounts = FailureCounts{};
    return c;
}

void ThermalSystem::triggerRodEjection() {
    // Weighted-random selection: each alive cylinder gets a weight based on
    // its current rod damage. Pristine engine → uniform random (every run
    // picks a different cylinder). Damaged engine → biased toward the worst
    // rod (the weakest link is most likely to fail). Either way, repeated
    // moneyshifts on the same engine produce different patterns.
    double totalWeight = 0.0;
    int aliveCount = 0;
    for (int i = 0; i < m_cylinderCount; ++i) {
        if (m_cylinderDead[i]) continue;
        const double damage = 1.0 - m_cylinders[i].rod;
        totalWeight += 1.0 + damage * 5.0;
        ++aliveCount;
    }
    if (aliveCount == 0) return;

    double pick = m_unit(m_rng) * totalWeight;
    int target = -1;
    for (int i = 0; i < m_cylinderCount; ++i) {
        if (m_cylinderDead[i]) continue;
        const double damage = 1.0 - m_cylinders[i].rod;
        const double w = 1.0 + damage * 5.0;
        pick -= w;
        if (pick <= 0.0) {
            target = i;
            break;
        }
    }
    if (target < 0) {
        // Fallback: pick first alive cylinder (should be unreachable).
        for (int i = 0; i < m_cylinderCount; ++i) {
            if (!m_cylinderDead[i]) { target = i; break; }
        }
    }
    if (target < 0) return;
    killCylinderById(target);
    m_catastrophicPending = true;
}

// Mark a specific cylinder dead, zero its mechanical components, damage
// the main bearing slightly. Used by both probabilistic moneyshift rolls
// and oil-starvation-triggered ejections.
void ThermalSystem::killCylinderById(int target) {
    if (target < 0 || target >= m_cylinderCount) return;
    if (m_cylinderDead[target]) return;

    m_cylinderDead[target] = true;
    m_cylinders[target].rod        = 0.0;
    m_cylinders[target].rodBearing = 0.0;
    m_cylinders[target].piston     = 0.0;
    m_engineWide.mainBearing  = std::max(0.0, m_engineWide.mainBearing - 0.08);
    m_engineWide.crankshaft   = std::max(0.0, m_engineWide.crankshaft  - 0.08);
    m_engineWide.cylinderHead = std::max(0.0, m_engineWide.cylinderHead - 0.04);
}

void ThermalSystem::applyMoneyshiftDamage(double /*rpm*/, double /*redline*/) {
    // Deprecated entry point; damage is now applied continuously in
    // detectMoneyshift while over-rev conditions persist. Kept as a stub so
    // the symbol still exists in case anything links to it.
}

void ThermalSystem::evaluateValveFloat(double dt, double rpm, double revLimitRpm) {
    // Like over-rev damage, valve float is referenced to the rev limiter: the
    // valvetrain only loses control once the engine is pushed past the limiter,
    // not while it's revving normally up to it.
    if (revLimitRpm <= 1.0) return;
    const double ratio = rpm / revLimitRpm;
    if (ratio <= kValveFloatRatioThresh) return;

    const double floatProbPerSec =
        std::max(0.0, (ratio - kValveFloatRatioThresh) * kValveFloatProbCoeff);
    const double pStep = floatProbPerSec * dt;
    for (int i = 0; i < m_cylinderCount; ++i) {
        if (m_unit(m_rng) < pStep) {
            if (m_unit(m_rng) < 0.5) {
                m_cylinders[i].intakeValve  -= kValveFloatDamage;
            } else {
                m_cylinders[i].exhaustValve -= kValveFloatDamage;
            }
            m_bentValvePending[i] = true;
        }
    }
}

void ThermalSystem::clampAllHealth() {
    for (auto &c : m_cylinders) {
        c.headGasket   = clamp01(c.headGasket);
        c.pistonRings  = clamp01(c.pistonRings);
        c.piston       = clamp01(c.piston);
        c.rod          = clamp01(c.rod);
        c.rodBearing   = clamp01(c.rodBearing);
        c.intakeValve  = clamp01(c.intakeValve);
        c.exhaustValve = clamp01(c.exhaustValve);
    }
    m_engineWide.cylinderHead = clamp01(m_engineWide.cylinderHead);
    m_engineWide.camshaft     = clamp01(m_engineWide.camshaft);
    m_engineWide.crankshaft   = clamp01(m_engineWide.crankshaft);
    m_engineWide.mainBearing  = clamp01(m_engineWide.mainBearing);
    m_engineWide.waterPump    = clamp01(m_engineWide.waterPump);
    m_engineWide.oilPump      = clamp01(m_engineWide.oilPump);
}

// --------------------------------------------------------------------------
// Pump controls
// --------------------------------------------------------------------------

void ThermalSystem::setCoolantPumpEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(m_lock);
    m_coolantPumpEnabled = enabled;
}
void ThermalSystem::setOilPumpEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(m_lock);
    m_oilPumpEnabled = enabled;
}
bool ThermalSystem::isCoolantPumpEnabled() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_coolantPumpEnabled;
}
bool ThermalSystem::isOilPumpEnabled() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_oilPumpEnabled;
}

// --------------------------------------------------------------------------
// Live thermal readouts
// --------------------------------------------------------------------------

double ThermalSystem::getCoolantTempC() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return celcius(m_coolantTempK);
}
double ThermalSystem::getOilTempC() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return celcius(m_oilTempK);
}
double ThermalSystem::getOilPressurePsi() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_oilPressurePa / units::psi;
}
double ThermalSystem::getCylinderWallTempC(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 0.0;
    return celcius(m_wallTempK[i]);
}
double ThermalSystem::getCylinderWallTempK(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return kInitialWallK;
    return m_wallTempK[i];
}

// --------------------------------------------------------------------------
// Damage readouts
// --------------------------------------------------------------------------

ThermalSystem::CylinderComponents ThermalSystem::getCylinderComponents(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return {};
    return m_cylinders[i];
}
ThermalSystem::EngineWideComponents ThermalSystem::getEngineWideComponents() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_engineWide;
}

double ThermalSystem::getCylinderAggregateHealth(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 0.0;
    const auto &c = m_cylinders[i];
    double v = c.headGasket;
    v = std::min(v, c.pistonRings);
    v = std::min(v, c.piston);
    v = std::min(v, c.rod);
    v = std::min(v, c.rodBearing);
    v = std::min(v, c.intakeValve);
    v = std::min(v, c.exhaustValve);
    return v;
}

double ThermalSystem::getTopEndHealth() const {
    std::lock_guard<std::mutex> lock(m_lock);
    double valveAvg = 0.0;
    for (const auto &c : m_cylinders) valveAvg += 0.5 * (c.intakeValve + c.exhaustValve);
    valveAvg /= std::max(1, m_cylinderCount);
    return (m_engineWide.cylinderHead + m_engineWide.camshaft + valveAvg) / 3.0;
}

double ThermalSystem::getMidHealth() const {
    std::lock_guard<std::mutex> lock(m_lock);
    double sum = 0.0;
    for (const auto &c : m_cylinders) {
        sum += (c.headGasket + c.pistonRings + c.piston) / 3.0;
    }
    return sum / std::max(1, m_cylinderCount);
}

double ThermalSystem::getBottomEndHealth() const {
    std::lock_guard<std::mutex> lock(m_lock);
    double cylSum = 0.0;
    for (const auto &c : m_cylinders) {
        cylSum += 0.5 * (c.rod + c.rodBearing);
    }
    cylSum /= std::max(1, m_cylinderCount);
    return (cylSum + m_engineWide.crankshaft + m_engineWide.mainBearing) / 3.0;
}

bool ThermalSystem::isCylinderSeized(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return false;
    const auto &c = m_cylinders[i];
    if (m_engineWide.mainBearing < kSeizureMainBearingThresh) return true;
    return c.rodBearing < kSeizureRodBearingThresh
        || c.pistonRings < kSeizureRingThresh;
}

bool ThermalSystem::isCylinderDead(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return false;
    return m_cylinderDead[i];
}

bool ThermalSystem::isEngineSeized() const {
    std::lock_guard<std::mutex> lock(m_lock);
    return m_engineSeized;
}

double ThermalSystem::getComponentHealth(int i, ComponentId component) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) {
        // Engine-wide components ignore the cylinder index.
        switch (component) {
            case ComponentId::CylinderHead: return m_engineWide.cylinderHead;
            case ComponentId::Camshaft:     return m_engineWide.camshaft;
            case ComponentId::Crankshaft:   return m_engineWide.crankshaft;
            case ComponentId::MainBearing:  return m_engineWide.mainBearing;
            case ComponentId::WaterPump:    return m_engineWide.waterPump;
            case ComponentId::OilPump:      return m_engineWide.oilPump;
            default: return 0.0;
        }
    }
    const auto &c = m_cylinders[i];
    switch (component) {
        case ComponentId::HeadGasket:   return c.headGasket;
        case ComponentId::PistonRings:  return c.pistonRings;
        case ComponentId::Piston:       return c.piston;
        case ComponentId::Rod:          return c.rod;
        case ComponentId::RodBearing:   return c.rodBearing;
        case ComponentId::IntakeValve:  return c.intakeValve;
        case ComponentId::ExhaustValve: return c.exhaustValve;
        case ComponentId::CylinderHead: return m_engineWide.cylinderHead;
        case ComponentId::Camshaft:     return m_engineWide.camshaft;
        case ComponentId::Crankshaft:   return m_engineWide.crankshaft;
        case ComponentId::MainBearing:  return m_engineWide.mainBearing;
        case ComponentId::WaterPump:    return m_engineWide.waterPump;
        case ComponentId::OilPump:      return m_engineWide.oilPump;
    }
    return 0.0;
}

double ThermalSystem::getSeizureForceMultiplier(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 1.0;
    const auto &c = m_cylinders[i];
    // Hard kill only: damaged-but-not-seized cylinders still get force from
    // the (already-attenuated) combustion pressure. Adding another multiplier
    // here would double-count the power loss.
    if (m_engineWide.mainBearing < kSeizureMainBearingThresh) return 0.0;
    if (c.rodBearing  < kSeizureRodBearingThresh) return 0.0;
    if (c.pistonRings < kSeizureRingThresh)       return 0.0;
    return 1.0;
}

double ThermalSystem::aggregateHealthLocked(int i) const {
    if (i < 0 || i >= m_cylinderCount) return 1.0;
    const auto &c = m_cylinders[i];
    return std::min({c.headGasket, c.pistonRings, c.piston,
                     c.rod, c.rodBearing,
                     c.intakeValve, c.exhaustValve});
}

// --------------------------------------------------------------------------
// Combustion-physics hooks
// --------------------------------------------------------------------------

bool ThermalSystem::shouldMisfire(int i) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return false;
    // Inline seizure check — never re-lock from inside a locked block.
    if (m_engineWide.mainBearing < kSeizureMainBearingThresh) return true;
    const auto &c = m_cylinders[i];
    if (c.rodBearing  < kSeizureRodBearingThresh) return true;
    if (c.pistonRings < kSeizureRingThresh)       return true;

    // 30% damage = 2.4% misfire rate (occasional miss audible at idle)
    // 60% damage = 19% misfire rate (clearly rough running)
    // 90% damage = 64% misfire rate (engine barely fires)
    const double worst = std::min({c.pistonRings, c.headGasket,
                                   c.intakeValve, c.exhaustValve, c.piston});
    const double dmg = 1.0 - worst;
    if (dmg <= 0.0) return false;
    const double p = dmg * dmg * 0.88;
    return m_unit(m_rng) < p;
}

double ThermalSystem::sampleCombustionEfficiency(int i) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 1.0;
    const auto &c = m_cylinders[i];

    // Baseline efficiency = min of components that bound how much of the
    // combustion energy can be converted to chamber pressure.
    double base = std::min({c.headGasket, c.pistonRings, c.piston});

    // Valves bound the AIR available to burn — affects efficiency too.
    const double valveAvg = 0.5 * (c.intakeValve + c.exhaustValve);
    base *= 0.4 + 0.6 * valveAvg;

    // Small engine-wide tax for top-end wear (cam wear shifts valve timing).
    const double globalTax = 0.6 + 0.4 * std::min(
        m_engineWide.camshaft, m_engineWide.cylinderHead);
    base *= globalTax;

    // Overheat power derate — the engine goes sluggish when coolant runs hot
    // (heat soak / timing retard), so a failed cooling system is felt immediately,
    // not just via slow gasket damage. No effect at normal temperature.
    const double coolantC = celcius(m_coolantTempK);
    if (coolantC > kThermalDerateStartC) {
        base *= std::max(kThermalDerateFloor,
            1.0 - (coolantC - kThermalDerateStartC) * kThermalDeratePerC);
    }

    // Cycle-to-cycle variance. Real engines vary ~2-3% even when healthy.
    // Damage scales it up but never to extreme levels — at full damage
    // total variance caps at ~25%, not 50%+ like before. Big swings were
    // making the exhaust sound choppy/poppy.
    const double baselineVar = 0.025;
    const double damageVar = (1.0 - c.pistonRings) * 0.20
                           + (1.0 - c.headGasket) * 0.12;
    const double totalVar = baselineVar + damageVar;
    const double u1 = m_unit(m_rng);
    const double u2 = m_unit(m_rng);
    const double dev = (u1 + u2 - 1.0);
    const double sample = base * (1.0 + totalVar * dev);

    return clamp01(sample);
}

double ThermalSystem::getBlowbyMultiplier(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 1.0;
    const auto &c = m_cylinders[i];
    // Blown gasket leaks straight to the next cylinder / outside. Damaged
    // rings let gas bypass the piston into the crankcase. Both scale blowby
    // way up. Healthy → 1.0, fully blown gasket → 30x, fully shot rings →
    // 15x; both combined → 45x.
    const double dGasket = 1.0 - c.headGasket;
    const double dRings  = 1.0 - c.pistonRings;
    return 1.0 + dGasket * 30.0 + dRings * 15.0;
}

double ThermalSystem::sampleKnockImpulse(int i) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 0.0;
    if (m_cylinderDead[i]) return 0.0;
    const auto &c = m_cylinders[i];

    // Knock is DETERMINISTIC, not stochastic. Real engine knock isn't a
    // random "occasionally fires" event — once a cylinder is damaged enough
    // that end-gas auto-ignites, EVERY firing produces some knock. What
    // changes with damage is the LOUDNESS, not the probability. This is the
    // key fix for the "random THUMP" feel from before.
    const double damage = std::max({
        1.0 - c.piston,
        1.0 - c.pistonRings,
        (1.0 - c.intakeValve)  * 0.6,
        (1.0 - c.exhaustValve) * 0.6
    });
    if (damage < 0.50) return 0.0;

    const double dz = (damage - 0.50) / 0.50;        // 0..1
    // Smoothly ramping amplitude. At threshold = barely audible. At full
    // damage = clearly audible but still a light click, not a thump.
    return dz * dz * 9.0e7;
}

double ThermalSystem::sampleMisfireBackfire(int /*i*/) {
    // No backfire pop. Misfires are heard as a missing exhaust pulse, not a
    // bang. Method kept (returns 0) so the bridge ABI stays stable.
    return 0.0;
}

double ThermalSystem::getRodKnockLevel(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 0.0;
    if (m_cylinderDead[i]) return 0.0;
    const auto &c = m_cylinders[i];
    const double damage = std::max({1.0 - m_engineWide.mainBearing,
                                    1.0 - c.rod,
                                    1.0 - c.rodBearing});
    // Real engines don't knock until bearings are well-worn. 65% deadzone
    // means a 50%-damaged bearing is still inaudible — only the truly
    // sloppy ones produce the characteristic deep tock.
    return audioDeadzone(damage, 0.65);
}

double ThermalSystem::getPistonSlapLevel(int i) const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return 0.0;
    if (m_cylinderDead[i]) return 0.0;
    const auto &c = m_cylinders[i];
    const double damage = std::max(1.0 - c.piston, 1.0 - c.pistonRings);
    return audioDeadzone(damage, 0.70);
}

double ThermalSystem::getValveClatterLevel(int /*i*/) const {
    // Disabled — the per-event resonator drive at BDC crossings produced
    // dense popping/clicking that didn't match any realistic engine sound.
    // Damaged valves now express themselves through reduced VE → smaller
    // exhaust pulses, plus misfires when valves are bent badly enough.
    return 0.0;
}

double ThermalSystem::getBearingWhineLevel() const {
    std::lock_guard<std::mutex> lock(m_lock);
    const double damage = 1.0 - m_engineWide.mainBearing;
    // Whine = latest-emerging, very damaged bearings only.
    return audioDeadzone(damage, 0.75) * 0.4;
}

double ThermalSystem::getBearingDragFactor() const {
    std::lock_guard<std::mutex> lock(m_lock);
    if (m_cylinderCount <= 0) return 0.0;
    // Worst of the rod-bearing wear (averaged over cylinders) and main-bearing
    // wear. Friction climbs roughly LINEARLY with wear from a small deadzone, so
    // the engine grows progressively sluggish as the bearings go — not fine until
    // it suddenly seizes at the end.
    double rodWear = 0.0;
    for (int i = 0; i < m_cylinderCount; ++i) {
        rodWear += 1.0 - m_cylinders[i].rodBearing;
    }
    rodWear /= m_cylinderCount;
    const double mainWear = 1.0 - m_engineWide.mainBearing;
    const double wear = std::max(rodWear, mainWear);
    // Linear ramp from ~5% wear: drag begins biting early and grows in step with
    // wear, so revs sag proportionally the whole way down to seizure.
    constexpr double kDragWearThresh = 0.05;
    if (wear <= kDragWearThresh) return 0.0;
    const double t = (wear - kDragWearThresh) / (1.0 - kDragWearThresh);
    return t * m_bearingDragRandom;
}

double ThermalSystem::getBlockHumLevel() const {
    // Block hum was an always-on rumble that drowned everything out at low
    // damage. Removed — damage character now comes entirely from the per-
    // event resonators above plus the asymmetric exhaust note from dead
    // cylinders. Method stays for ABI / sympathetic linkage.
    return 0.0;
}

bool ThermalSystem::popBentValveEvent(int i) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return false;
    const bool v = m_bentValvePending[i];
    m_bentValvePending[i] = false;
    return v;
}
bool ThermalSystem::popMoneyshiftEvent() {
    std::lock_guard<std::mutex> lock(m_lock);
    const bool v = m_moneyshiftPending;
    m_moneyshiftPending = false;
    return v;
}

void ThermalSystem::debugForceCatastrophe() {
    std::lock_guard<std::mutex> lock(m_lock);
    rollAndApplyCatastrophicFailures(1.0);
}

bool ThermalSystem::popCatastrophicEvent() {
    std::lock_guard<std::mutex> lock(m_lock);
    const bool v = m_catastrophicPending;
    m_catastrophicPending = false;
    return v;
}

// --------------------------------------------------------------------------
// Hooks called from CombustionChamber
// --------------------------------------------------------------------------

void ThermalSystem::recordPeakPressure(int i, double pa) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return;
    if (pa > m_peakPressurePa[i]) m_peakPressurePa[i] = pa;
}
void ThermalSystem::recordPeakTemp(int i, double k) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return;
    if (k > m_peakTempK[i]) m_peakTempK[i] = k;
}
void ThermalSystem::accumulateWallHeat(int i, double joules) {
    std::lock_guard<std::mutex> lock(m_lock);
    if (i < 0 || i >= m_cylinderCount) return;
    m_wallTempK[i] += joules / kWallThermalMassJK;
}
