#include "../include/piston_engine_simulator.h"

#include "../include/constants.h"
#include "../include/units.h"

#include <cmath>
#include <assert.h>
#include <chrono>
#include <set>

#include <iostream> 

PistonEngineSimulator::PistonEngineSimulator() {
    m_engine = nullptr;
    m_transmission = nullptr;
    m_vehicle = nullptr;
    m_delayFilters = nullptr;

    m_crankConstraints = nullptr;
    m_cylinderWallConstraints = nullptr;
    m_linkConstraints = nullptr;
    m_crankshaftFrictionConstraints = nullptr;
    m_crankshaftLinks = nullptr;

    m_exhaustFlowStagingBuffer = nullptr;

    m_lastCylAngle = nullptr;

    m_knockResonY1 = nullptr;
    m_knockResonY2 = nullptr;
    m_knockReson2Y1 = nullptr;
    m_knockReson2Y2 = nullptr;
    m_knockBurstSamples = nullptr;
    m_knockBurstAmp = nullptr;

    m_growlLP1 = 0.0;
    m_growlLP2 = 0.0;
    m_catastropheSizeFactor = 1.0;
    m_catastropheRodWeight = 1.0;
    m_catastrophePistonWeight = 1.0;
    m_catastropheValveWeight = 1.0;
    m_crashActive = false;
    m_impactNext = 0;

    m_derivativeFilter.m_dt = 1.0;
    m_fluidSimulationSteps = 8;
}

PistonEngineSimulator::~PistonEngineSimulator() {
    assert(m_crankConstraints == nullptr);
    assert(m_cylinderWallConstraints == nullptr);
    assert(m_linkConstraints == nullptr);
    assert(m_crankshaftFrictionConstraints == nullptr);
    assert(m_exhaustFlowStagingBuffer == nullptr);
    assert(m_delayFilters == nullptr);
    assert(m_knockResonY1 == nullptr);
    assert(m_lastCylAngle == nullptr);
}

void PistonEngineSimulator::loadSimulation(Engine *engine, Vehicle *vehicle, Transmission *transmission) {
    Simulator::loadSimulation(engine, vehicle, transmission);

    m_engine = engine;
    m_vehicle = vehicle;
    m_transmission = transmission;

    const int crankCount = m_engine->getCrankshaftCount();
    const int cylinderCount = m_engine->getCylinderCount();
    const int linkCount = cylinderCount * 2;

    if (crankCount <= 0) return;

    m_crankConstraints = new atg_scs::FixedPositionConstraint[crankCount];
    m_cylinderWallConstraints = new atg_scs::LineConstraint[cylinderCount];
    m_linkConstraints = new atg_scs::LinkConstraint[linkCount];
    m_crankshaftFrictionConstraints = new atg_scs::RotationFrictionConstraint[crankCount];
    m_crankshaftLinks = new atg_scs::ClutchConstraint[crankCount - 1];
    m_delayFilters = new DelayFilter[cylinderCount];

    const double ks = 5000;
    const double kd = 10;

    for (int i = 0; i < crankCount; ++i) {
        Crankshaft *outputShaft = m_engine->getCrankshaft(0);
        Crankshaft *crankshaft = m_engine->getCrankshaft(i);

        m_crankConstraints[i].setBody(&crankshaft->m_body);
        m_crankConstraints[i].setWorldPosition(
            crankshaft->getPosX(),
            crankshaft->getPosY());
        m_crankConstraints[i].setLocalPosition(0.0, 0.0);
        m_crankConstraints[i].m_kd = kd;
        m_crankConstraints[i].m_ks = ks;

        crankshaft->m_body.p_x = crankshaft->getPosX();
        crankshaft->m_body.p_y = crankshaft->getPosY();
        crankshaft->m_body.theta = 0;
        crankshaft->m_body.m =
            crankshaft->getMass() + crankshaft->getFlywheelMass();
        crankshaft->m_body.I = crankshaft->getMomentOfInertia();

        m_crankshaftFrictionConstraints[i].m_minTorque = -crankshaft->getFrictionTorque();
        m_crankshaftFrictionConstraints[i].m_maxTorque = crankshaft->getFrictionTorque();
        m_crankshaftFrictionConstraints[i].setBody(&m_engine->getCrankshaft(i)->m_body);

        m_system->addRigidBody(&m_engine->getCrankshaft(i)->m_body);
        m_system->addConstraint(&m_crankConstraints[i]);
        m_system->addConstraint(&m_crankshaftFrictionConstraints[i]);

        if (crankshaft != outputShaft) {
            atg_scs::ClutchConstraint *crankLink = &m_crankshaftLinks[i - 1];
            crankLink->setBody1(&outputShaft->m_body);
            crankLink->setBody2(&crankshaft->m_body);

            m_system->addConstraint(crankLink);
        }
    }

    m_transmission->addToSystem(m_system, &m_vehicleMass, m_vehicle, m_engine);
    m_vehicle->addToSystem(m_system, &m_vehicleMass);

    m_vehicleDrag.initialize(&m_vehicleMass, m_vehicle);
    m_system->addConstraint(&m_vehicleDrag);

    m_vehicleMass.reset();
    m_vehicleMass.m = 1.0;
    m_vehicleMass.I = 1.0;
    m_system->addRigidBody(&m_vehicleMass);

    for (int i = 0; i < cylinderCount; ++i) {
        Piston *piston = m_engine->getPiston(i);
        ConnectingRod *connectingRod = piston->getRod();

        CylinderBank *bank = piston->getCylinderBank();
        const double dx = std::cos(bank->getAngle() + constants::pi / 2);
        const double dy = std::sin(bank->getAngle() + constants::pi / 2);

        m_cylinderWallConstraints[i].setBody(&piston->m_body);
        m_cylinderWallConstraints[i].m_dx = dx;
        m_cylinderWallConstraints[i].m_dy = dy;
        m_cylinderWallConstraints[i].m_local_x = 0.0;
        m_cylinderWallConstraints[i].m_local_y = piston->getWristPinLocation();
        m_cylinderWallConstraints[i].m_p0_x = bank->getX();
        m_cylinderWallConstraints[i].m_p0_y = bank->getY();
        m_cylinderWallConstraints[i].m_ks = ks;
        m_cylinderWallConstraints[i].m_kd = kd;

        piston->setCylinderConstraint(&m_cylinderWallConstraints[i]);

        m_linkConstraints[i * 2 + 0].setBody1(&connectingRod->m_body);
        m_linkConstraints[i * 2 + 0].setBody2(&piston->m_body);
        m_linkConstraints[i * 2 + 0]
            .setLocalPosition1(0.0, connectingRod->getLittleEndLocal());
        m_linkConstraints[i * 2 + 0].setLocalPosition2(0.0, piston->getWristPinLocation());
        m_linkConstraints[i * 2 + 0].m_ks = ks;
        m_linkConstraints[i * 2 + 0].m_kd = kd;

        double journal_x = 0.0, journal_y = 0.0;
        if (connectingRod->getMasterRod() == nullptr) {
            Crankshaft *crankshaft = connectingRod->getCrankshaft();
            crankshaft->getRodJournalPositionLocal(
                connectingRod->getJournal(),
                &journal_x,
                &journal_y);
            m_linkConstraints[i * 2 + 1].setBody2(&crankshaft->m_body);
        }
        else {
            connectingRod->getMasterRod()->getRodJournalPositionLocal(
                connectingRod->getJournal(),
                &journal_x,
                &journal_y);
            m_linkConstraints[i * 2 + 1].setBody2(&connectingRod->getMasterRod()->m_body);
        }

        m_linkConstraints[i * 2 + 1].setBody1(&connectingRod->m_body);
        m_linkConstraints[i * 2 + 1]
            .setLocalPosition1(0.0, connectingRod->getBigEndLocal());
        m_linkConstraints[i * 2 + 1]
            .setLocalPosition2(journal_x, journal_y);
        m_linkConstraints[i * 2 + 1].m_ks = ks;
        m_linkConstraints[i * 2 + 0].m_kd = kd;

        piston->m_body.m = piston->getMass();
        piston->m_body.I = 1.0;

        connectingRod->m_body.m = connectingRod->getMass();
        connectingRod->m_body.I = connectingRod->getMomentOfInertia();

        m_system->addRigidBody(&piston->m_body);
        m_system->addRigidBody(&connectingRod->m_body);
        m_system->addConstraint(&m_linkConstraints[i * 2 + 0]);
        m_system->addConstraint(&m_linkConstraints[i * 2 + 1]);
        m_system->addConstraint(&m_cylinderWallConstraints[i]);
        m_system->addForceGenerator(m_engine->getChamber(i));
    }

    m_dyno.connectCrankshaft(m_engine->getOutputCrankshaft());
    m_system->addConstraint(&m_dyno);

    m_starterMotor.connectCrankshaft(m_engine->getOutputCrankshaft());
    m_starterMotor.m_maxTorque = m_engine->getStarterTorque();
    m_starterMotor.m_rotationSpeed = -m_engine->getStarterSpeed();
    m_system->addConstraint(&m_starterMotor);

    placeAndInitialize();
    initializeSynthesizer();
}

double PistonEngineSimulator::getAverageOutputSignal() const {
    double sum = 0.0;
    for (int i = 0; i < m_engine->getExhaustSystemCount(); ++i) {
        sum += m_engine->getExhaustSystem(i)->getSystem()->pressure();
    }

    return sum / m_engine->getExhaustSystemCount();
}

void PistonEngineSimulator::configureResonator(
    double freq, double Q, double &a1, double &a2) const
{
    const double sampleRate = static_cast<double>(getSimulationFrequency());
    const double omega = 2.0 * constants::pi * freq / sampleRate;
    const double r = std::exp(-constants::pi * freq / (Q * sampleRate));
    a1 =  2.0 * r * std::cos(omega);
    a2 = -r * r;
}

// Trigger one money-shift impact into the next pool voice as a SHAPED NOISE
// BURST (no tones — see ImpactVoice). `bigness` (0..1) maps a small sharp bright
// clack to a huge deep loud boom: bigger = deeper end-cutoff, more makeup gain,
// longer cutoff sweep & decay. End-cutoff is tilted by which part failed
// (rod/crank deeper, valve brighter). Everything else is randomized per hit.
void PistonEngineSimulator::fireImpactVoice(double scale, double bigness) {
    constexpr double kTwoPi = 2.0 * constants::pi;
    const double sr = static_cast<double>(getSimulationFrequency());
    std::uniform_real_distribution<double> u01(0.0, 1.0);
    auto rnd = [&] { return u01(m_audioRng); };

    bigness = std::min(1.0, std::max(0.0, bigness));
    ImpactVoice &v = m_impact[m_impactNext];
    m_impactNext = (m_impactNext + 1) % kImpactVoices;

    // Lowpass cutoff sweeps from a bright CRACK down to a low combustion THUD.
    // (one-pole coef = exp(-2*pi*fc/sr); a BIGGER coef = LOWER cutoff = duller.)
    const double pitchTilt = m_catastropheValveWeight - m_catastropheRodWeight;
    const double fcStart = 2500.0 + 4000.0 * rnd();              // bright attack edge
    const double fcEnd   = (160.0 + 620.0 * (1.0 - bigness))     // deep for big hits
                         * std::pow(2.0, 0.5 * pitchTilt) * (0.85 + 0.3 * rnd());
    v.lpA     = std::exp(-kTwoPi * fcStart / sr);
    v.lpAEnd  = std::exp(-kTwoPi * fcEnd   / sr);
    const double sweepMs = 6.0 + 55.0 * bigness;                 // big = slower body
    v.lpACoef = std::exp(-1.0 / (sweepMs * 0.001 * sr));
    v.lp1 = 0.0;
    v.lp2 = 0.0;

    const double decayMs = 22.0 + 240.0 * bigness;               // big booms ring on
    v.env      = 1.0;
    v.envDecay = std::exp(-1.0 / (decayMs * 0.001 * sr));
    v.amp = scale * (0.8 + 0.7 * bigness);                       // loudness vs debris

    // A broadband attack edge (~0.5-2ms) layered on top for the sharp transient.
    v.crackSamples = static_cast<int>((0.5 + 1.5 * rnd()) * 0.001 * sr);
    v.crackAmp     = scale * (0.6 + 0.6 * bigness);
}

// Advance one impact voice a single sample and return its output. Pure noise:
// a 2-pole lowpass on white noise whose cutoff sweeps down, plus a brief
// broadband attack edge. The lowpass is loudness-NORMALISED (gainComp) so the
// low thud lands as hard as the bright crack instead of vanishing — the sweep
// changes TIMBRE (bright->deep), the envelope controls LEVEL. Inactive voices
// cost only a comparison.
double PistonEngineSimulator::renderImpactVoice(ImpactVoice &v, double /*sampleRate*/) {
    constexpr double kEps = 1e-4;
    if (v.env <= kEps) return 0.0;
    std::uniform_real_distribution<double> noise(-1.0, 1.0);

    const double nz = noise(m_audioRng);
    v.lpA = v.lpAEnd + (v.lpA - v.lpAEnd) * v.lpACoef;      // sweep cutoff down
    v.lp1 = v.lpA * v.lp1 + (1.0 - v.lpA) * nz;
    v.lp2 = v.lpA * v.lp2 + (1.0 - v.lpA) * v.lp1;
    // Compensate the lowpass's RMS loss so deep cutoffs aren't inaudibly quiet.
    const double gainComp = std::sqrt((1.0 + v.lpA) / (1.0 - v.lpA));
    double out = v.lp2 * gainComp;
    if (v.crackSamples > 0) {
        out += nz * v.crackAmp;
        v.crackSamples--;
    }
    out *= v.env * v.amp;
    v.env *= v.envDecay;
    return out;
}

void PistonEngineSimulator::placeAndInitialize() {
    const int cylinderCount = m_engine->getCylinderCount();
    for (int i = 0; i < cylinderCount; ++i) {
        ConnectingRod *rod = m_engine->getConnectingRod(i);

        if (rod->getRodJournalCount() != 0) {
            placeCylinder(i);
        }
    }

    for (int i = 0; i < cylinderCount; ++i) {
        placeCylinder(i);
    }

    for (int i = 0; i < cylinderCount; ++i) {
        m_engine->getChamber(i)->m_system.initialize(
            units::pressure(1.0, units::atm),
            m_engine->getChamber(i)->getVolume(),
            units::celcius(25.0)
        );

        Piston *piston = m_engine->getChamber(i)->getPiston();
        CylinderHead *head = m_engine->getChamber(i)->getCylinderHead();
        ExhaustSystem *exhaust = head->getExhaustSystem(piston->getCylinderIndex());
        const double exhaustLength =
            head->getHeaderPrimaryLength(piston->getCylinderIndex())
            + exhaust->getLength();
        const double speedOfSound = 343.0 * units::m / units::sec;
        const double delay = exhaustLength / speedOfSound;
        m_delayFilters[i].initialize(delay, 10000.0);
    }

    m_engine->getIgnitionModule()->reset();

    m_exhaustFlowStagingBuffer = new double[m_engine->getExhaustSystemCount()];

    const int cylCount = m_engine->getCylinderCount();
    m_lastCylAngle      = new double[cylCount]();
    m_knockResonY1      = new double[cylCount]();
    m_knockResonY2      = new double[cylCount]();
    m_knockReson2Y1     = new double[cylCount]();
    m_knockReson2Y2     = new double[cylCount]();
    m_knockBurstSamples = new int   [cylCount]();
    m_knockBurstAmp     = new double[cylCount]();
    m_previousCycleAngle = 0.0;

    // Configure damped-resonator filters. Form:
    //   y[n] = a1·y[n-1] + a2·y[n-2] + x[n]
    //   a1 =  2·r·cos(omega)
    //   a2 = -r²
    // Impulse response: r^n · sin((n+1)·omega) / sin(omega) (damped sinusoid).
    // Knock: 1.2 + 1.8 kHz with VERY low Q (2.5 / 2.0). At this Q the
    // resonator barely rings — its impulse response decays in ~2-3 ms,
    // giving a dry CLICK with no reverb tail. The engine block is a solid
    // damped structure; knock doesn't echo. This kills the "empty room"
    // character.
    configureResonator(1200.0,   2.5, m_knockResonA1,  m_knockResonA2);
    configureResonator(1800.0,   2.0, m_knockReson2A1, m_knockReson2A2);
}

void PistonEngineSimulator::placeCylinder(int i) {
    ConnectingRod *rod = m_engine->getConnectingRod(i);
    Piston *piston = m_engine->getPiston(i);
    CylinderBank *bank = piston->getCylinderBank();

    double p_x, p_y;
    if (rod->getMasterRod() != nullptr) {
        rod->getMasterRod()->getRodJournalPositionGlobal(rod->getJournal(), &p_x, &p_y);
    }
    else {
        rod->getCrankshaft()->getRodJournalPositionGlobal(rod->getJournal(), &p_x, &p_y);
    }

    // (bank->m_x + bank->m_dx * s - p_x)^2 + (bank->m_y + bank->m_dy * s - p_y)^2 = (rod->m_length)^2
    const double a = bank->getDx() * bank->getDx() + bank->getDy() * bank->getDy();
    const double b = -2 * bank->getDx() * (p_x - bank->getX()) - 2 * bank->getDy() * (p_y - bank->getY());
    const double c =
        (p_x - bank->getX()) * (p_x - bank->getX())
        + (p_y - bank->getY()) * (p_y - bank->getY())
        - rod->getLength() * rod->getLength();

    const double det = b * b - 4 * a * c;
    if (det < 0) return;

    const double sqrt_det = std::sqrt(det);
    const double s0 = (-b + sqrt_det) / (2 * a);
    const double s1 = (-b - sqrt_det) / (2 * a);

    const double s = std::max(s0, s1);
    if (s < 0) return;

    const double e_x = s * bank->getDx() + bank->getX();
    const double e_y = s * bank->getDy() + bank->getY();

    const double theta = ((e_y - p_y) > 0)
        ? std::acos((e_x - p_x) / rod->getLength())
        : 2 * constants::pi - std::acos((e_x - p_x) / rod->getLength());
    rod->m_body.theta = theta - constants::pi / 2;

    double cl_x, cl_y;
    rod->m_body.localToWorld(0, rod->getBigEndLocal(), &cl_x, &cl_y);
    rod->m_body.p_x += p_x - cl_x;
    rod->m_body.p_y += p_y - cl_y;

    piston->m_body.p_x = e_x;
    piston->m_body.p_y = e_y;
    piston->m_body.theta = bank->getAngle() + constants::pi;
}

void PistonEngineSimulator::simulateStep_() {
    const double timestep = getTimestep();
    IgnitionModule *im = m_engine->getIgnitionModule();
    im->update(timestep);

    // Tick the thermal/damage system before fluid flow so the per-cylinder
    // wall temps are up-to-date when chambers call flow() below.
    ThermalSystem *thermal = m_engine->getThermalSystem();
    if (thermal != nullptr) {
        const double rpmNow  = m_engine->getRpm();
        const double redline = units::toRpm(m_engine->getRedline());
        // Load proxy for the thermal model. The UI pedal can arrive via EITHER
        // setThrottle (-> getThrottle) OR the governor setSpeedControl (-> get
        // SpeedControl) — the macOS app uses the latter, so getThrottle alone is
        // always 0 and the coolant never saw the throttle (coolant tracked only
        // laggy wall heat-soak: it didn't heat under load and crept up on lift).
        // Take whichever is commanded so coolant heat tracks the actual pedal.
        const double throttle = std::max(m_engine->getThrottle(),
                                         m_engine->getSpeedControl());
        const double clutch   = (m_transmission != nullptr)
            ? m_transmission->getClutchPressure() : 1.0;
        const double speedMps = (m_vehicle != nullptr)
            ? m_vehicle->getSpeed() : 0.0;
        thermal->update(timestep, rpmNow, redline,
                        throttle, clutch, speedMps);
    }

    const int cylinderCount = m_engine->getCylinderCount();
    const bool engineSeized = thermal != nullptr && thermal->isEngineSeized();

    // === Wind-down after catastrophic damage ===
    // A real broken engine winds down over a few seconds — not instantly.
    // Friction from damaged parts is significant but not infinite. Even a
    // seized engine usually takes ~1-2 seconds for the flywheel to stop
    // (depending on its mass).
    //
    // Most moneyshifts don't actually seize the crank — they break the top
    // end / eject rods, and the engine winds down naturally from no power +
    // existing friction. We only apply explicit braking when the engine is
    // genuinely seized OR severely broken (>50% cylinders dead).
    if (thermal != nullptr && m_engine->getCrankshaftCount() > 0) {
        double brakeRate = 0.0;   // 1/s; v *= exp(-brakeRate * dt) per step
        if (engineSeized) {
            // Locked crank — wind down over ~1-2 sec. Half-life ~0.6 s.
            brakeRate = 1.2;
        } else {
            // Many dead cylinders → engine has minimal power + lots of drag.
            // Light braking so it decelerates noticeably faster than a coast.
            int deadCount = 0;
            for (int i = 0; i < cylinderCount; ++i) {
                if (thermal->isCylinderDead(i)) ++deadCount;
            }
            const double deadFrac = (cylinderCount > 0)
                ? static_cast<double>(deadCount) / cylinderCount
                : 0.0;
            if (deadFrac > 0.4) {
                brakeRate = 0.4 * (deadFrac - 0.4);   // gentle assist
            }
        }
        if (brakeRate > 0.0) {
            const double decay = std::exp(-brakeRate * timestep);
            for (int c = 0; c < m_engine->getCrankshaftCount(); ++c) {
                m_engine->getCrankshaft(c)->m_body.v_theta *= decay;
            }
        }

        // The crankshaft wind-down above doesn't touch the car's momentum,
        // which lives in the separate vehicle rotating mass — so once seized
        // the car would coast almost indefinitely on rolling resistance alone.
        // A locked/destroyed bottom end drags the driveline, so bleed the
        // vehicle mass down to a stop over a few seconds instead.
        constexpr double vehicleSeizureBrakeRate = 0.9;   // 1/s; half-life ~0.77 s
        if (engineSeized) {
            m_vehicleMass.v_theta *= std::exp(-vehicleSeizureBrakeRate * timestep);
        }
    }

    // === Worn-bearing FRICTION (oil starvation) ===
    // Worn / oil-starved bearings raise the engine's OWN friction. Rather than
    // bolt on an arbitrary external torque, we scale the crankshaft's real
    // friction parameter (getFrictionTorque) by wear: a wiped bearing can drag at
    // many times the engine's healthy friction. The engine must fight this, so it
    // grows progressively sluggish and the revs sag on their own — no hardcoded
    // rev drop. Because crank friction is Coulomb, the power it eats is torque×rpm,
    // so the loss grows with engine speed and high revs sag first. Updated every
    // step from current bearing wear; at zero wear the factor is 1 (untouched).
    if (thermal != nullptr && m_crankshaftFrictionConstraints != nullptr
        && m_engine->getCrankshaftCount() > 0) {
        const double drag = thermal->getBearingDragFactor();   // 0 .. ~1.7, linear in wear
        constexpr double kWornBearingFrictionGain = 10.0;      // friction multiplier at full drag
        const double frictionMul = 1.0 + kWornBearingFrictionGain * drag;
        for (int c = 0; c < m_engine->getCrankshaftCount(); ++c) {
            const double total = m_engine->getCrankshaft(c)->getFrictionTorque() * frictionMul;
            m_crankshaftFrictionConstraints[c].m_maxTorque =  total;
            m_crankshaftFrictionConstraints[c].m_minTorque = -total;
        }
    }
    for (int i = 0; i < cylinderCount; ++i) {
        if (im->getIgnitionEvent(i)) {
            // No ignitions if the engine is seized (main bearing failed →
            // crank can't turn → nothing fires).
            // A dead cylinder (rod ejected, etc.) doesn't fire either — it's
            // an empty hole moving with the crank.
            // Otherwise, roll for misfire from accumulated damage. A misfire
            // skips combustion this cycle — no chamber pressure peak →
            // missing exhaust pulse → audible "miss" in the engine rhythm.
            const bool dead = thermal != nullptr && thermal->isCylinderDead(i);
            const bool misfire = !dead && !engineSeized
                              && thermal != nullptr
                              && thermal->shouldMisfire(i);
            if (!dead && !engineSeized && !misfire) {
                m_engine->getChamber(i)->ignite();
            }
        }

        m_engine->getChamber(i)->update(timestep);
    }

    for (int i = 0; i < cylinderCount; ++i) {
        m_engine->getChamber(i)->resetLastTimestepExhaustFlow();
        m_engine->getChamber(i)->resetLastTimestepIntakeFlow();
    }

    const int exhaustSystemCount = m_engine->getExhaustSystemCount();
    const int intakeCount = m_engine->getIntakeCount();
    const double fluidTimestep = timestep / m_fluidSimulationSteps;
    for (int i = 0; i < m_fluidSimulationSteps; ++i) {
        for (int j = 0; j < exhaustSystemCount; ++j) {
            m_engine->getExhaustSystem(j)->process(fluidTimestep);
        }

        for (int j = 0; j < intakeCount; ++j) {
            m_engine->getIntake(j)->process(fluidTimestep, m_engine->getFuelTrim());
            m_engine->getIntake(j)->m_flowRate += m_engine->getIntake(j)->m_flow;
        }

        for (int j = 0; j < cylinderCount; ++j) {
            m_engine->getChamber(j)->flow(fluidTimestep);
        }
    }

    im->resetIgnitionEvents();

    // 4π cycle-boundary detection. A "wrap" is any large drop in cycle angle
    // (the crankshaft normalizes back to 0 from near 4π). Triggers per-cycle
    // damage rules in the thermal system.
    if (thermal != nullptr && m_engine->getCrankshaftCount() > 0) {
        const double currentAngle = m_engine->getOutputCrankshaft()->getCycleAngle();
        if (currentAngle < m_previousCycleAngle - constants::pi) {
            thermal->onCycleBoundary();
        }
        m_previousCycleAngle = currentAngle;
    }
}

double PistonEngineSimulator::getTotalExhaustFlow() const {
    double totalFlow = 0.0;
    for (int i = 0; i < m_engine->getCylinderCount(); ++i) {
        totalFlow += m_engine->getChamber(i)->getLastTimestepExhaustFlow();
    }

    return totalFlow;
}

void PistonEngineSimulator::endFrame() {
    Simulator::endFrame();

    if (m_engine == nullptr) {
        return;
    }

    const double frameTimestep = simulationSteps() * getTimestep();
    const int cylinderCount = m_engine->getCylinderCount();
    for (int i = 0; i < m_engine->getIntakeCount(); ++i) {
        m_engine->getIntake(i)->m_flowRate /= frameTimestep;
    }
}

void PistonEngineSimulator::destroy() {
    if (m_system != nullptr) m_system->reset();

    if (m_crankConstraints != nullptr) delete[] m_crankConstraints;
    if (m_cylinderWallConstraints != nullptr) delete[] m_cylinderWallConstraints;
    if (m_linkConstraints != nullptr) delete[] m_linkConstraints;
    if (m_crankshaftFrictionConstraints != nullptr) delete[] m_crankshaftFrictionConstraints;
    if (m_exhaustFlowStagingBuffer != nullptr) delete[] m_exhaustFlowStagingBuffer;
    if (m_system != nullptr) delete m_system;
    if (m_delayFilters != nullptr) delete[] m_delayFilters;
    delete[] m_lastCylAngle;
    delete[] m_knockResonY1;
    delete[] m_knockResonY2;
    delete[] m_knockReson2Y1;
    delete[] m_knockReson2Y2;
    delete[] m_knockBurstSamples;
    delete[] m_knockBurstAmp;

    m_crankConstraints = nullptr;
    m_cylinderWallConstraints = nullptr;
    m_linkConstraints = nullptr;
    m_crankshaftFrictionConstraints = nullptr;
    m_exhaustFlowStagingBuffer = nullptr;
    m_lastCylAngle = nullptr;
    m_knockResonY1 = nullptr;
    m_knockResonY2 = nullptr;
    m_knockReson2Y1 = nullptr;
    m_knockReson2Y2 = nullptr;
    m_knockBurstSamples = nullptr;
    m_knockBurstAmp = nullptr;
    m_system = nullptr;

    m_vehicle = nullptr;
    m_transmission = nullptr;
    m_engine = nullptr;
    m_delayFilters = nullptr;
}

void PistonEngineSimulator::writeToSynthesizer() {
    const int exhaustSystemCount = m_engine->getExhaustSystemCount();
    for (int i = 0; i < exhaustSystemCount; ++i) {
        m_exhaustFlowStagingBuffer[i] = 0;
    }

    const double attenuation = std::min(std::abs(filteredEngineSpeed()), 40.0) / 40.0;
    const double attenuation_3 = attenuation * attenuation * attenuation;

    static double lastValveLift[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };

    const double timestep = getTimestep();
    const int cylinderCount = m_engine->getCylinderCount();
    ThermalSystem *thermal = m_engine->getThermalSystem();

    // ===== AUDIO-MIX TUNING =====
    // Damage audio is a SUBTLE LAYER on top of the engine sound. The engine
    // is always the dominant thing you hear; damage tells you something is
    // wrong without competing for attention. The whole damage layer scales
    // with attenuation_3 (engine-load proxy) so it blends with the exhaust
    // and never appears as a separate "thing" louder than the engine itself.
    //
    // Resonator output amplitude is roughly excitation / sin(omega), which
    // means a 190 Hz resonator amplifies its input ~37x. Excitation values
    // below are sized so the resonator outputs peak around 5-15% of exhaust
    // pulse amplitude even at full damage. With a 60% deadzone in the level
    // curve, this means audible damage only exists between 60-100% damage,
    // and even then it's a subtle additive layer.
    constexpr int kKnockBurstSamples  = 12;   // tighter click character
    constexpr double kKnockExciteMax  = 2.5e8;
    constexpr double kWhinePeak       = 2.0e6;

    // Knock = piston crown contacting the valve. The impact velocity tracks
    // engine speed, so the energy (and loudness) scales with rpm². A quadratic
    // ramp keeps knock nearly silent at idle and only brings it up as the
    // engine spins faster, matching the physical impact.
    constexpr double kKnockFullRpm = 4000.0;   // rpm at which knock is full
    // Click-envelope decay per sample. Lower = tighter click, shorter ring/
    // reverb tail. Tightened so each knock reads as a dry tick.
    constexpr double kKnockEnvDecay = 0.92;

    // Gate damage audio on engine rotation (silent at zero RPM).
    const double rpmForAudio = m_engine->getRpm();
    const double rpmFactor = std::min(1.0,
        std::max(0.0, (rpmForAudio - 50.0) / 250.0));

    std::uniform_real_distribution<double> noise(-1.0, 1.0);

    // ===== PASS 1: Per-cylinder exhaust pulses =====
    // (Knock moved to Pass 2 — it's now triggered by crank position, not
    // ignition, so it fires at consistent intervals regardless of misfires.)
    for (int i = 0; i < cylinderCount; ++i) {
        Piston *piston = m_engine->getPiston(i);
        CylinderBank *bank = piston->getCylinderBank();
        CylinderHead *head = m_engine->getHead(bank->getIndex());
        ExhaustSystem *exhaust = head->getExhaustSystem(piston->getCylinderIndex());
        CombustionChamber *chamber = m_engine->getChamber(i);

        const double exhaustLength =
            head->getHeaderPrimaryLength(piston->getCylinderIndex())
            + exhaust->getLength();

        // Dead cylinders contribute NO exhaust pulse — there's a hole in the
        // block where this cylinder used to be (or the rod is gone, the
        // piston isn't sealing, etc.). The asymmetric "missing cylinder"
        // sound that results is the audio signature of a catastrophic event.
        const bool dead = thermal != nullptr && thermal->isCylinderDead(i);
        const double cylAlive = dead ? 0.0 : 1.0;

        double exhaustFlow =
            cylAlive * attenuation_3 * 1600 * (
                1.0 * (chamber->m_exhaustRunnerAndPrimary.pressure() - units::pressure(1.0, units::atm))
                + 0.1 * chamber->m_exhaustRunnerAndPrimary.dynamicPressure(1.0, 0.0)
                + 0.1 * chamber->m_exhaustRunnerAndPrimary.dynamicPressure(-1.0, 0.0));

        lastValveLift[i] = head->exhaustValveLift(piston->getCylinderIndex());

        const double delayedExhaustPulse =
            m_delayFilters[i].fast_f(exhaustFlow);

        ExhaustSystem *exhaustSystem = head->getExhaustSystem(piston->getCylinderIndex());
        m_exhaustFlowStagingBuffer[exhaustSystem->getIndex()] +=
            head->getSoundAttenuation(piston->getCylinderIndex())
            * (exhaustSystem->getAudioVolume() * delayedExhaustPulse / cylinderCount)
            * (1 / (exhaustLength * exhaustLength));
    }

    // ===== PASS 2: Rotation-driven damage audio =====
    // Mechanical damage sounds — rod knock, piston slap, valve clatter,
    // bearing whine — come from the engine BLOCK. They are PHYSICAL events
    // tied to crankshaft rotation: rod loading reverses at TDC, piston
    // velocity reverses at BDC, bearings whine because they're spinning.
    //
    // Therefore: NO damage audio plays unless the engine is actually rotating.
    // Below ~200 RPM the engine is effectively stopped and silent. Damage
    // events only trigger on real crank-angle crossings, so a still engine
    // produces no triggers; the resonators decay to zero on their own.
    //
    // Damage audio is mixed AFTER the delay filter and exhaust attenuation
    // because it radiates from the block, not down the exhaust runner.
    // Normalized (~[-1,1]) DRY catastrophe signal sent alongside the exhaust to
    // the synthesizer — it bypasses the reverberant exhaust convolution so the
    // boom/clanks stay clean and dry. Set inside the block below.
    double dryDamage = 0.0;

    if (thermal != nullptr && cylinderCount > 0
        && m_engine->getCrankshaftCount() > 0 && rpmFactor > 0.0) {

        const double crankCycleAngle =
            m_engine->getOutputCrankshaft()->getCycleAngle();
        IgnitionModule *im = m_engine->getIgnitionModule();
        const double rpm = rpmForAudio;

        constexpr double kFourPi = 4.0 * constants::pi;
        constexpr double kTwoPi  = 2.0 * constants::pi;
        constexpr double kOnePi  = constants::pi;
        constexpr double kThreePi = 3.0 * constants::pi;

        for (int i = 0; i < cylinderCount; ++i) {
            const double firingAngle = im->getFiringAngle(i);
            double cylAngle = std::fmod(
                crankCycleAngle - firingAngle + kFourPi, kFourPi);
            const double lastAngle = m_lastCylAngle[i];

            // TDC compression crossing — cylAngle wraps from ~4π back to ~0
            // once per cycle. This is when the piston is at top, where knock
            // (detonation) physically occurs. Triggering knock HERE rather
            // than on the ignition event makes it consistent: it fires once
            // per cycle per cylinder at the same crank position, regardless
            // of whether the cylinder actually ignited (misfires don't make
            // knock come and go).
            const bool crossedTDC_C =
                (lastAngle > kThreePi && cylAngle < kOnePi);

            const bool dead = thermal->isCylinderDead(i);

            if (!dead && crossedTDC_C) {
                const double knockLevel = thermal->sampleKnockImpulse(i);
                if (knockLevel > 0.0) {
                    // Arm a dry knock click on this cylinder. m_knockBurstAmp
                    // holds the click's current amplitude (decays fast);
                    // m_knockResonY1 is the per-cylinder noise LPF state.
                    m_knockBurstAmp[i] = knockLevel;
                }
            }

            m_lastCylAngle[i] = cylAngle;
        }

        // ====================================================================
        // CATASTROPHE AUDIO — a money-shift grenade, modelled as a STOCHASTIC
        // CHAIN OF IMPACTS. The engine lets go: one big initial BANG, then a
        // chaotic, decaying flurry of secondary bangs as broken parts are flung
        // around inside the block and ejected. Each bang is a punchy IMPACT VOICE
        // (sharp crack + downward pitch-swept thump + inharmonic metallic ring —
        // see fireImpactVoice / renderImpactVoice). A randomized point process
        // schedules them: dense right after the bang, thinning and quieting as the
        // wreckage settles, with occasional "bounce" clusters (a part rattling to
        // rest: clang..clang.clk.clk). Pitch / amplitude / timing / count are all
        // random so no two grenades sound alike. The bus is soft-clipped (tanh) so
        // the low body stays a round tone while the sharp attacks saturate for
        // punch; the master-bus soft-limiter then sets the final loudness.
        // ====================================================================
        constexpr double kDebrisRate    = 40.0;  // secondary hits/sec at full intensity
        constexpr double kIntensityTau  = 0.55;  // s, debris-energy decay constant
        constexpr double kDurMin        = 1.2;    // s, event-length floor
        constexpr double kDurRand       = 1.5;    // -> 1.2-2.7 s
        constexpr double kBounceProb    = 0.22;   // chance a hit starts a bounce cluster
        constexpr double kBigSecondProb = 0.07;   // chance a secondary is a big piece

        // Soft-clip ceiling for the WET damage bus (knock + growl).
        constexpr double kDamageSoftClip = 6.5e8;

        const double sampleRate = static_cast<double>(getSimulationFrequency());

        double damageAudio = 0.0;   // WET: knock + growl (convolved with exhaust)
        double crashBus    = 0.0;   // DRY: the whole grenade (bang + debris)

        if (thermal->popCatastrophicEvent()) {
            const auto counts = thermal->popCatastropheCounts();
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            m_catastropheSizeFactor = std::sqrt(
                std::max(1.0, static_cast<double>(cylinderCount) / 4.0));

            // Failure-type weights tilt impact pitch (rod/crank deep, valve high).
            const double rodW    = 1.0 + counts.rods * 2.5 + (counts.crank ? 6.0 : 0.0);
            const double pistonW = 1.0 + counts.pistons * 2.0 + counts.gaskets * 0.7
                                 + (counts.cam ? 2.5 : 0.0);
            const double valveW  = 1.0 + counts.valves * 2.2 + (counts.cam ? 1.5 : 0.0);
            const double total   = rodW + pistonW + valveW;
            m_catastropheRodWeight    = rodW    / total;
            m_catastrophePistonWeight = pistonW / total;
            m_catastropheValveWeight  = valveW  / total;

            // THE primary BANG — the biggest, deepest, loudest impact, heard
            // alone for an instant before the debris flurry starts.
            fireImpactVoice(1.0, 0.9 + 0.1 * u01(m_audioRng));

            m_crashActive   = true;
            m_crashElapsed  = 0.0;
            m_crashDuration = kDurMin + kDurRand * u01(m_audioRng);
            m_bounceCount   = 0;
        }

        // ---- Chaotic debris scheduler — the secondary bangs ----
        if (m_crashActive) {
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            m_crashElapsed += timestep;
            if (m_crashElapsed >= m_crashDuration) m_crashActive = false;

            // Overall energy decays as the wreckage loses momentum and settles.
            const double intensity = std::exp(-m_crashElapsed / kIntensityTau);

            // A part rattling to rest: a burst of hits with shrinking gap & amp.
            if (m_bounceCount > 0) {
                m_bounceTimer -= timestep;
                if (m_bounceTimer <= 0.0) {
                    fireImpactVoice(m_bounceAmp, 0.12 + 0.28 * u01(m_audioRng));
                    m_bounceAmp      *= 0.6;
                    m_bounceInterval *= 0.7;
                    m_bounceTimer     = m_bounceInterval;
                    m_bounceCount--;
                }
            }

            // Poisson-distributed secondary impacts at a decaying rate.
            const double rate = kDebrisRate * intensity * m_catastropheSizeFactor;
            if (u01(m_audioRng) < rate * timestep) {
                const double amp = intensity * (0.3 + 0.7 * u01(m_audioRng));
                if (u01(m_audioRng) < kBounceProb) {
                    // start a bounce cluster (a single part settling)
                    m_bounceCount    = 3 + static_cast<int>(u01(m_audioRng) * 4);
                    m_bounceAmp      = amp;
                    m_bounceInterval = 0.03 + 0.05 * u01(m_audioRng);
                    m_bounceTimer    = 0.0;
                } else {
                    // mostly small debris; rarely a big secondary piece lets go.
                    const double r = u01(m_audioRng);
                    const double bigness = (u01(m_audioRng) < kBigSecondProb)
                        ? 0.78 + 0.18 * u01(m_audioRng)
                        : 0.55 * r * r;
                    fireImpactVoice(amp, bigness);
                }
            }
        }

        // ---- Render the impact voice pool into the dry crash bus ----
        for (int v = 0; v < kImpactVoices; ++v) {
            crashBus += renderImpactVoice(m_impact[v], sampleRate);
        }

        // Step the per-cylinder accent resonators (rod/piston/valve) and the
        // per-cylinder knock click, summing into damageAudio.
        // Per-cylinder knock click — DRY band-limited noise burst, no resonator
        // ring (a tight ~1.7ms click, no reverb tail). m_knockBurstAmp[i] is the
        // decaying envelope; m_knockResonY1[i] is a one-pole LPF state colouring
        // the noise to ~1.3 kHz. Knock loudness follows a QUADRATIC rpm ramp
        // (piston-vs-valve impact energy ∝ velocity² ∝ rpm²) so it is near-silent
        // at idle and a faint layer UNDER the engine note as revs climb.
        for (int i = 0; i < cylinderCount; ++i) {
            if (m_knockBurstAmp[i] > 1.0) {
                const double rawNoise = noise(m_audioRng);
                m_knockResonY1[i] = 0.74 * m_knockResonY1[i] + 0.26 * rawNoise;
                const double rpmRamp = std::min(1.0, rpm / kKnockFullRpm);
                const double knockRpmScale = rpmRamp * rpmRamp;
                damageAudio += m_knockResonY1[i] * m_knockBurstAmp[i]
                             * 0.025 * knockRpmScale;   // wet: on the exhaust path
                m_knockBurstAmp[i] *= kKnockEnvDecay;
            }
        }

        // === Worn / oil-starved bearing RUMBLE ===
        // A bad bearing makes a rough low-mid metallic rumble that ROLLS with the
        // crank — near-silent at cranking, growing with engine speed. It is a
        // LAYER under the engine note (the engine bogging from the added bearing
        // FRICTION is the real damage cue), not a steady wind/whine. Band-limited
        // noise amplitude-modulated by crank rotation so it pulses per revolution;
        // loudness scales with (rpm/redline)² so it tracks engine speed instead of
        // being full-volume the moment the engine turns over.
        constexpr double kBearingCutoffHz = 220.0;   // rough low-mid texture
        constexpr double kBearingAudioGain = 6.0;    // LPF makeup; layer, not dominant
        const double bearingLevel = thermal->getBearingWhineLevel();   // 0..0.4
        const double redlineRpm = units::toRpm(m_engine->getRedline());
        if (bearingLevel > 0.0 && redlineRpm > 0.0) {
            const double a = std::exp(-kTwoPi * kBearingCutoffHz / sampleRate);
            const double rawNoise = noise(m_audioRng);
            m_growlLP1 = a * m_growlLP1 + (1.0 - a) * rawNoise;
            m_growlLP2 = a * m_growlLP2 + (1.0 - a) * m_growlLP1;
            // Rotational AM: rumble "rolls" with each revolution, not a flat wind.
            m_bearingPhase += kTwoPi * (rpm / 60.0) / sampleRate;
            if (m_bearingPhase > kTwoPi) m_bearingPhase -= kTwoPi;
            const double s = std::sin(m_bearingPhase);
            const double rumbleMod = 0.3 + 0.7 * s * s;          // peaky, 2x/rev
            // Loudness grows with engine speed (quadratic) — quiet at cranking.
            const double speed = std::min(1.0, rpm / redlineRpm);
            const double speedGain = speed * speed;
            damageAudio += bearingLevel * speedGain
                         * kWhinePeak * kBearingAudioGain * m_growlLP2 * rumbleMod;
        }

        // === Worn-bearing SQUEAK / whine (dry metal-on-metal) ===
        // A SLIGHT, intermittent high whistle that grows with wear — the dry
        // bearing squeal. It is a narrow resonator excited by noise (so it is
        // breathy/unstable, NOT a clean tone or piano), with the pitch slowly
        // DRIFTING and the level FLICKERING in and out (both re-rolled randomly
        // every ~40-90 ms) so it reads as a randomized squeak rather than a steady
        // tone or wind. Driven by wear (getBearingDragFactor, emerges from ~5%
        // wear) so it comes up gradually as the bearings go.
        constexpr double kSqueakFreqMin   = 1500.0;  // Hz
        constexpr double kSqueakFreqRand  = 2200.0;  // -> 1.5-3.7 kHz, drifting
        constexpr double kSqueakQ         = 22.0;    // narrow whistle (noise-excited = breathy)
        constexpr double kSqueakGlide     = 0.0025;  // per-sample glide toward target pitch/level
        constexpr double kSqueakFullDrag  = 0.8;     // wear-drag at which the squeak is fully in
        constexpr double kSqueakPeak      = 4.0e4;   // VERY slight — a faint background detail (was 1.6e5)
        const double squeakWear = thermal->getBearingDragFactor();   // 0 .. ~1.7, linear in wear
        if (squeakWear > 0.0 && redlineRpm > 0.0) {
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            if (--m_squeakReconfig <= 0) {
                m_squeakTargetFreq = kSqueakFreqMin + u01(m_audioRng) * kSqueakFreqRand;
                const double r = u01(m_audioRng);
                m_squeakTargetAmp  = r * r * r;          // skewed low -> mostly quiet, occasional squeak
                m_squeakReconfig   = static_cast<int>((0.04 + 0.05 * u01(m_audioRng)) * sampleRate);
            }
            m_squeakFreq += (m_squeakTargetFreq - m_squeakFreq) * kSqueakGlide;
            m_squeakAmp  += (m_squeakTargetAmp  - m_squeakAmp ) * kSqueakGlide;
            configureResonator(m_squeakFreq, kSqueakQ, m_squeakA1, m_squeakA2);
            const double omega = kTwoPi * m_squeakFreq / sampleRate;
            const double y = m_squeakA1 * m_squeakY1 + m_squeakA2 * m_squeakY2
                           + noise(m_audioRng) * std::sin(omega);   // gain-comp excitation
            m_squeakY2 = m_squeakY1;
            m_squeakY1 = y;
            const double wearGain = std::min(1.0, squeakWear / kSqueakFullDrag);
            const double rpmGate  = std::min(1.0, rpm / redlineRpm);
            // Low floor (0.1) so the squeak is especially quiet at low rpm and
            // only fills in as revs rise.
            damageAudio += y * m_squeakAmp * wearGain * (0.1 + 0.9 * rpmGate)
                         * kSqueakPeak;
        }

        // WET damage (knock + growl) rides the exhaust path (convolution etc.),
        // gated by load + rpm so it sits as a layer on the engine note. The
        // tanh keeps dense moments from clipping hard.
        if (exhaustSystemCount > 0) {
            const double loadGate = attenuation_3 * rpmFactor;
            const double wet = kDamageSoftClip
                * std::tanh(damageAudio / kDamageSoftClip);
            const double perChannel = wet * loadGate / exhaustSystemCount;
            for (int j = 0; j < exhaustSystemCount; ++j) {
                m_exhaustFlowStagingBuffer[j] += perChannel;
            }
        }

        // DRY catastrophe -> ~[-1,1], on the dry synthesizer path that BYPASSES
        // the reverberant exhaust convolution (no echo), mixed at the master bus.
        // The voices are already balanced (primary bang loudest, debris below) so
        // a single tanh handles the whole grenade: the low body stays a round tone
        // while the sharp attack transients saturate for punch. kCrashNorm is set
        // so the primary bang saturates toward full scale; the master-bus soft-
        // limiter sets the final loudness.
        constexpr double kCrashNorm = 1.7;
        double cat = std::tanh(crashBus / kCrashNorm) * rpmFactor;
        dryDamage = std::max(-1.0, std::min(1.0, cat));
    }

    synthesizer().writeInput(m_exhaustFlowStagingBuffer, dryDamage);
}
