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

    m_rodResonY1 = nullptr;
    m_rodResonY2 = nullptr;
    m_rodBurstSamples = nullptr;
    m_rodBurstAmp = nullptr;

    m_pistonResonY1 = nullptr;
    m_pistonResonY2 = nullptr;
    m_pistonBurstSamples = nullptr;
    m_pistonBurstAmp = nullptr;

    m_valveResonY1 = nullptr;
    m_valveResonY2 = nullptr;
    m_valveBurstSamples = nullptr;
    m_valveBurstAmp = nullptr;

    m_growlLP1 = 0.0;
    m_growlLP2 = 0.0;
    m_catastropheSizeFactor = 1.0;
    m_catastropheRodWeight = 1.0;
    m_catastrophePistonWeight = 1.0;
    m_catastropheValveWeight = 1.0;
    m_catastropheRateMul = 1.0;
    m_boomY1 = 0.0;
    m_boomY2 = 0.0;
    m_boomA1 = 0.0;
    m_boomA2 = 0.0;
    m_boomBurst = 0;
    m_boomBurstAmp = 0.0;
    m_boomBlastSamples = 0;
    m_boomBlastAmp = 0.0;
    m_boomBlastLP = 0.0;
    m_grindLP1 = 0.0;
    m_grindLP2 = 0.0;
    m_grindLP3 = 0.0;
    m_crashVoiceNext = 0;
    m_clankCountdown = 0;
    m_clanksRemaining = 0;
    m_clankAmp = 0.0;
    m_blockHumY1 = 0.0;
    m_blockHumY2 = 0.0;

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
    assert(m_rodResonY1 == nullptr);
    assert(m_pistonResonY1 == nullptr);
    assert(m_valveResonY1 == nullptr);
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
    m_rodResonY1        = new double[cylCount]();
    m_rodResonY2        = new double[cylCount]();
    m_rodBurstSamples   = new int   [cylCount]();
    m_rodBurstAmp       = new double[cylCount]();
    m_pistonResonY1     = new double[cylCount]();
    m_pistonResonY2     = new double[cylCount]();
    m_pistonBurstSamples= new int   [cylCount]();
    m_pistonBurstAmp    = new double[cylCount]();
    m_valveResonY1      = new double[cylCount]();
    m_valveResonY2      = new double[cylCount]();
    m_valveBurstSamples = new int   [cylCount]();
    m_valveBurstAmp     = new double[cylCount]();
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
    // Rod / catastrophic deep thump. Q=3.5 — very short ring so impacts
    // read as solid HITS, not booming reverberations. A real engine block
    // is heavily damped; a rod hitting it makes a dull THUD, not a gong.
    configureResonator(110.0,    3.5, m_rodResonA1,    m_rodResonA2);
    // Piston: mid-band crushing mode. Q=3 — broad, impact-like.
    configureResonator(650.0,    3.0, m_pistonResonA1, m_pistonResonA2);
    // Valve clatter: very low Q=2 — basically a band-passed click, no tone.
    configureResonator(2200.0,   2.0, m_valveResonA1,  m_valveResonA2);
    // Block hum: global, ~70 Hz Q=6. A continuously trickled-in low rumble
    // that comes alive as overall damage rises. Body of a "sick" engine.
    configureResonator(70.0,     6.0, m_blockHumA1,    m_blockHumA2);
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
        const double throttle = m_engine->getThrottle();
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
    delete[] m_rodResonY1;
    delete[] m_rodResonY2;
    delete[] m_rodBurstSamples;
    delete[] m_rodBurstAmp;
    delete[] m_pistonResonY1;
    delete[] m_pistonResonY2;
    delete[] m_pistonBurstSamples;
    delete[] m_pistonBurstAmp;
    delete[] m_valveResonY1;
    delete[] m_valveResonY2;
    delete[] m_valveBurstSamples;
    delete[] m_valveBurstAmp;

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
    m_rodResonY1 = nullptr;
    m_rodResonY2 = nullptr;
    m_rodBurstSamples = nullptr;
    m_rodBurstAmp = nullptr;
    m_pistonResonY1 = nullptr;
    m_pistonResonY2 = nullptr;
    m_pistonBurstSamples = nullptr;
    m_pistonBurstAmp = nullptr;
    m_valveResonY1 = nullptr;
    m_valveResonY2 = nullptr;
    m_valveBurstSamples = nullptr;
    m_valveBurstAmp = nullptr;
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
    constexpr int kRodBurstSamples    = 14;
    constexpr int kPistonBurstSamples = 12;
    constexpr int kValveBurstSamples  = 8;

    constexpr double kKnockExciteMax  = 2.5e8;
    constexpr double kRodExciteMax    = 8.0e6;   // peak output ~3e8 = subtle
    constexpr double kPistonExciteMax = 3.5e6;
    constexpr double kValveExciteMax  = 7.0e6;
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
        // CATASTROPHE AUDIO — a money-shift grenade. Two phases:
        //
        //   1. THE BOOM — the engine lets go: a single LOUD detonation. Made of
        //      a sharp low-mid BLAST transient (a short noise burst — the "punch"
        //      of the explosion) layered over a deep, punchy low resonator body.
        //      It is the dominant event and is heard ALONE before the debris.
        //
        //   2. THE CLANKS — parts breaking loose and tumbling inside the block:
        //      a randomized SEQUENCE of discrete DULL metallic clanks. Each clank
        //      is a short noise burst through a LOW-Q resonator, so it THUNKS and
        //      dies fast — a dead, inharmonic metal-on-metal clank, NOT a ringing
        //      tone (high-Q resonators ring like piano strings, which is wrong).
        //      The TIME BETWEEN clanks is irregular and randomized — clusters,
        //      gaps, and a general thinning-out as the debris settles. Pitch,
        //      Q, amplitude, count and timing are ALL randomized per event, so
        //      no two grenades sound alike.
        //
        // No sustained noise anywhere (that just sounds like wind). Every element
        // is a sharp transient. The whole damage bus is soft-clipped (tanh) so it
        // can be loud without harsh digital clipping that wrecks speakers.
        // ====================================================================

        // IMPORTANT — two facts drive every amplitude/frequency choice here,
        // both VERIFIED with an offline resonator sim (see money-shift memory):
        //  (1) A resonator's gain scales ~1/frequency (a 60 Hz hit gets ~50x the
        //      gain of a 3 kHz hit), so to make every element come out at the
        //      loudness we ask for, burst amplitude = targetOutput*sin(omega).
        //  (2) Real speakers roll off below ~100 Hz. A 45-80 Hz "boom" is simply
        //      INAUDIBLE on them (that's why earlier booms vanished), and low
        //      clanks get lost (everything sounded "all high pitch"). So the
        //      boom's punch lives at ~110-170 Hz and clanks are tilted to favour
        //      the audible low-mids.

        // ---- BOOM (initial detonation) — the dominant event ----
        // An explosion = a sharp BROADBAND BLAST (fast-decaying noise burst, the
        // "crack/punch") layered over a punchy LOW BODY (resonator thump). A pure
        // low tone alone does NOT read as a bang; the broadband blast is what
        // makes it a BANG. The blast decays fast (~10ms) so it's a crack, not a
        // sustained "fart"; it's lowpassed so it's a deep crack, not bright hiss.
        constexpr double kBoomFreqMin    = 80.0;    // Hz, low body thump
        constexpr double kBoomFreqRand   = 55.0;    // -> 80-135 Hz
        constexpr double kBoomQMin       = 5.0;     // punchy body (longer: ~90-160ms)
        constexpr double kBoomQRand      = 4.0;     // -> Q 5-9
        constexpr double kBoomOutPeak    = 5.5e8;   // TARGET body output (LOUD)
        constexpr int    kBoomBurstMin   = 2;       // body resonator excitation samples
        constexpr int    kBoomBurstRand  = 3;       // -> 2-4
        constexpr double kBoomBurstNorm  = 1.3;     // multi-sample energy correction
        constexpr double kBoomBlastAmp   = 9.0e8;   // broadband blast (the crack)
        constexpr double kBoomBlastMs    = 55.0;    // blast duration (longer)
        constexpr double kBoomBlastMsRand = 22.0;
        constexpr double kBoomBlastDecay = 0.9974;  // per-sample (~11ms, longer tail)
        constexpr double kBoomBlastLPA   = 0.74;    // lowpass ~2.2 kHz (deep crack)

        // ---- BREAKING DEBRIS ----
        // Original-style metallic IMPACTS (rod/piston/valve block resonators +
        // a short grind-noise burst) PLUS occasional quieter MINI-BOOMS (low
        // thumps = small, cleaner versions of the main bang, with a short = less
        // static blast). Fired by a decaying-rate event window.
        constexpr double kImpactNoisePeak  = 1.2e8;  // grind-noise per-impact amp
        constexpr double kImpactRateStart  = 26.0;   // hits/sec at onset
        constexpr double kImpactRateDecay  = 2.6;    // thins out over the event
        constexpr double kMiniBoomProb     = 0.38;   // fraction of hits = mini-booms
        constexpr double kMiniBoomFreqMin  = 60.0;   // Hz
        constexpr double kMiniBoomFreqRand = 120.0;  // -> 60-180 Hz
        constexpr double kMiniBoomQMin     = 3.0;
        constexpr double kMiniBoomQRand    = 4.0;    // -> Q 3-7
        constexpr int    kMiniBoomBurstMin = 4;      // short burst (slight static)
        constexpr int    kMiniBoomBurstRand = 6;
        constexpr double kMiniBoomOutPeak  = 3.0e8;  // mini-boom target output
        // Length/timing randomness only ever EXTENDS the event (floor stays at
        // the approved baseline) so no money shift is ever sparser/shorter than
        // before — it just varies upward.
        constexpr double kEventDurSec      = 0.9;    // debris window FLOOR (baseline)
        constexpr double kEventDurRand     = 1.1;    // -> 0.9-2.0s (more varied length)
        constexpr double kEventStartMs     = 90.0;   // boom-alone delay before debris

        // Soft-clip ceiling for the WET damage bus (knock + growl).
        constexpr double kDamageSoftClip = 6.5e8;

        const double sampleRate = static_cast<double>(getSimulationFrequency());

        double damageAudio = 0.0;   // WET: knock + growl (convolved with exhaust)
        double boomBus     = 0.0;   // DRY: the BANG (must dominate)
        double clankBus    = 0.0;   // DRY: breaking debris (kept below the bang)

        // Fire one metallic IMPACT — a rod/piston/valve letting go (the original
        // breaking sound): kick the per-cylinder block resonators (weighted by
        // what actually failed) plus a short grind-noise burst for impact texture.
        auto fireImpact = [&](double ampScale) {
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            const int cyl =
                static_cast<int>(u01(m_audioRng) * cylinderCount) % cylinderCount;
            m_rodBurstSamples[cyl]    = kRodBurstSamples    * 2;
            m_rodBurstAmp[cyl]        = kRodExciteMax    * ampScale
                                      * m_catastropheRodWeight    * 0.8;
            m_pistonBurstSamples[cyl] = kPistonBurstSamples * 2;
            m_pistonBurstAmp[cyl]     = kPistonExciteMax * ampScale
                                      * m_catastrophePistonWeight * 0.8;
            m_valveBurstSamples[cyl]  = kValveBurstSamples  * 2;
            m_valveBurstAmp[cyl]      = kValveExciteMax  * ampScale
                                      * m_catastropheValveWeight  * 0.8;
            m_grindLP1 = std::min(
                m_grindLP1 + ampScale * kImpactNoisePeak * m_catastropheSizeFactor,
                2.0 * kImpactNoisePeak);
        };

        // Fire one MINI-BOOM — a quieter, cleaner version of the main bang: a low
        // resonator thump (random freq/Q) kicked by a SHORT noise burst (a little
        // "static", less than the main blast). Voiced through the resonator pool
        // so several can overlap. Gain-compensated so its loudness is predictable.
        auto fireMiniBoom = [&](double ampScale) {
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            const int v = m_crashVoiceNext;
            m_crashVoiceNext = (m_crashVoiceNext + 1) % kCrashVoices;
            const double freq = kMiniBoomFreqMin
                              + u01(m_audioRng) * kMiniBoomFreqRand;
            const double Q = kMiniBoomQMin + u01(m_audioRng) * kMiniBoomQRand;
            configureResonator(freq, Q, m_crashVA1[v], m_crashVA2[v]);
            const double omega = kTwoPi * freq / sampleRate;
            m_crashVBurst[v]    = kMiniBoomBurstMin
                + static_cast<int>(u01(m_audioRng) * kMiniBoomBurstRand);
            m_crashVBurstAmp[v] = ampScale * kMiniBoomOutPeak * std::sin(omega);
            m_crashVY1[v] = 0.0;
            m_crashVY2[v] = 0.0;
        };

        if (thermal->popCatastrophicEvent()) {
            const auto counts = thermal->popCatastropheCounts();
            const double sizeFactor = std::sqrt(
                std::max(1.0, static_cast<double>(cylinderCount) / 4.0));
            std::uniform_real_distribution<double> u01(0.0, 1.0);

            m_catastropheSizeFactor = sizeFactor;

            // Per-failure-type weights tilt the clank pitch: rod/crank failures
            // clank LOW (deep), valve/cam failures clank HIGH (bright).
            const double rodW =
                1.0 + counts.rods * 2.5 + (counts.crank ? 6.0 : 0.0);
            const double pistonW =
                1.0 + counts.pistons * 2.0 + counts.gaskets * 0.7
                    + (counts.cam ? 2.5 : 0.0);
            const double valveW =
                1.0 + counts.valves * 2.2 + (counts.cam ? 1.5 : 0.0);
            const double total = rodW + pistonW + valveW;
            m_catastropheRodWeight    = rodW    / total;
            m_catastrophePistonWeight = pistonW / total;
            m_catastropheValveWeight  = valveW  / total;
            const double sevScale = std::min(3.0, total / 4.0);
            // Gentle, CLAMPED loudness factor (worse failure = a bit louder).
            // NOT sizeFactor*sevScale — that hit ~5x and slammed the soft-clip
            // into buzzy distortion. The synth's leveler sets overall loudness;
            // here we only need the relative balance (boom > clanks) to hold.
            const double sevAmp = 0.8 + 0.25 * std::min(2.0, sevScale);

            // ---- THE BOOM ----
            // Audible-band (~110-170 Hz) resonator excited by a short NOISE burst
            // (punchy thud + harmonics, gain-compensated to come out LOUD) plus a
            // broadband CLICK for the sharp detonation crack. Frequency/Q/amp
            // randomized each event.
            const double boomFreq = kBoomFreqMin + u01(m_audioRng) * kBoomFreqRand;
            const double boomQ    = kBoomQMin    + u01(m_audioRng) * kBoomQRand;
            configureResonator(boomFreq, boomQ, m_boomA1, m_boomA2);
            const double boomOmega = kTwoPi * boomFreq / sampleRate;
            m_boomY1 = 0.0;
            m_boomY2 = 0.0;
            m_boomBurst = kBoomBurstMin
                        + static_cast<int>(u01(m_audioRng) * kBoomBurstRand);
            m_boomBurstAmp = kBoomOutPeak * (0.85 + 0.3 * u01(m_audioRng))
                           * sevAmp * std::sin(boomOmega) / kBoomBurstNorm;
            m_boomBlastSamples = static_cast<int>(
                (kBoomBlastMs + u01(m_audioRng) * kBoomBlastMsRand)
                * 0.001 * sampleRate);
            m_boomBlastAmp = kBoomBlastAmp * (0.8 + 0.4 * u01(m_audioRng)) * sevAmp;
            m_boomBlastLP  = 0.0;

            // ---- Open the DEBRIS event window ----
            // Impacts + mini-booms fire over this window at a decaying rate; it
            // opens after a short delay so the boom is heard alone first.
            m_clankCountdown  = static_cast<int>(kEventStartMs * 0.001 * sampleRate);
            m_clankTotal      = static_cast<int>(
                sampleRate * (kEventDurSec + u01(m_audioRng) * kEventDurRand));
            m_clanksRemaining = m_clankTotal;
            m_clankAmp        = sevAmp;   // base amplitude scale for impacts
            // Randomize impact density (>=1, never sparser than baseline).
            m_catastropheRateMul = 1.0 + 0.4 * u01(m_audioRng);   // 1.0-1.4
        }

        // ---- Step THE BOOM (audible-band punchy detonation) ----
        // Resonator driven by a short INPUT noise burst (gives the resonator its
        // big low-frequency gain -> loud, punchy thud with harmonics) plus a
        // brief broadband click for the sharp attack crack.
        {
            double x = 0.0;
            if (m_boomBurst > 0) {
                x = noise(m_audioRng) * m_boomBurstAmp;
                m_boomBurst--;
            }
            const double y = m_boomA1 * m_boomY1 + m_boomA2 * m_boomY2 + x;
            m_boomY2 = m_boomY1;
            m_boomY1 = y;
            boomBus += y;
            // Explosive broadband blast — the sharp crack of the detonation.
            if (m_boomBlastSamples > 0) {
                const double bn = noise(m_audioRng);
                m_boomBlastLP = kBoomBlastLPA * m_boomBlastLP
                              + (1.0 - kBoomBlastLPA) * bn;
                boomBus += m_boomBlastLP * m_boomBlastAmp;
                m_boomBlastAmp *= kBoomBlastDecay;
                m_boomBlastSamples--;
            }
        }

        // ---- DEBRIS event window: metallic impacts + mini-booms ----
        // After a short boom-alone delay, fire hits at a rate that decays over the
        // event (dense as it lets go, thinning as it settles). Each hit is mostly
        // an original-style metallic IMPACT, sometimes a quieter MINI-BOOM. Every
        // parameter (timing, which-hit, amplitude, pitch) is randomized.
        if (m_clankCountdown > 0) {
            m_clankCountdown--;
        } else if (m_clanksRemaining > 0 && cylinderCount > 0) {
            m_clanksRemaining--;
            const double progress = 1.0 - static_cast<double>(m_clanksRemaining)
                                  / std::max(1, m_clankTotal);     // 0 -> 1
            const double rate = kImpactRateStart * m_catastropheRateMul
                * std::exp(-progress * kImpactRateDecay) * m_catastropheSizeFactor;
            std::uniform_real_distribution<double> u01(0.0, 1.0);
            if (u01(m_audioRng) < rate * timestep) {
                const double amp = m_clankAmp * (0.4 + 0.8 * u01(m_audioRng))
                                 * (1.0 - 0.5 * progress);   // settles, varied
                if (u01(m_audioRng) < kMiniBoomProb) fireMiniBoom(amp);
                else                                 fireImpact(amp);
            }
        }

        // ---- Grind-noise texture under the impacts (decays per impact) ----
        if (m_grindLP1 > 1.0) {
            const double rawNoise = noise(m_audioRng);
            constexpr double kLpfA = 0.82;            // ~1.4 kHz, no brittle hiss
            m_grindLP2 = kLpfA * m_grindLP2 + (1.0 - kLpfA) * rawNoise;
            m_grindLP3 = kLpfA * m_grindLP3 + (1.0 - kLpfA) * m_grindLP2;
            clankBus += m_grindLP3 * m_grindLP1 * 5.0;
            m_grindLP1 *= 0.9955;
        }

        // ---- Step the mini-boom voice pool ----
        {
            double clankOut = 0.0;
            for (int v = 0; v < kCrashVoices; ++v) {
                double x = 0.0;
                if (m_crashVBurst[v] > 0) {
                    x = noise(m_audioRng) * m_crashVBurstAmp[v];
                    m_crashVBurst[v]--;
                }
                const double y = m_crashVA1[v] * m_crashVY1[v]
                               + m_crashVA2[v] * m_crashVY2[v] + x;
                m_crashVY2[v] = m_crashVY1[v];
                m_crashVY1[v] = y;
                clankOut += y;
            }
            clankBus += clankOut;
        }

        // Step the per-cylinder accent resonators (rod/piston/valve) and the
        // per-cylinder knock click, summing into damageAudio.
        for (int i = 0; i < cylinderCount; ++i) {
            double rodIn = 0.0;
            if (m_rodBurstSamples[i] > 0) {
                rodIn = noise(m_audioRng) * m_rodBurstAmp[i];
                m_rodBurstSamples[i]--;
            }
            const double yR = m_rodResonA1 * m_rodResonY1[i]
                            + m_rodResonA2 * m_rodResonY2[i] + rodIn;
            m_rodResonY2[i] = m_rodResonY1[i];
            m_rodResonY1[i] = yR;

            double pistonIn = 0.0;
            if (m_pistonBurstSamples[i] > 0) {
                pistonIn = noise(m_audioRng) * m_pistonBurstAmp[i];
                m_pistonBurstSamples[i]--;
            }
            const double yP = m_pistonResonA1 * m_pistonResonY1[i]
                            + m_pistonResonA2 * m_pistonResonY2[i] + pistonIn;
            m_pistonResonY2[i] = m_pistonResonY1[i];
            m_pistonResonY1[i] = yP;

            double valveIn = 0.0;
            if (m_valveBurstSamples[i] > 0) {
                valveIn = noise(m_audioRng) * m_valveBurstAmp[i];
                m_valveBurstSamples[i]--;
            }
            const double yV = m_valveResonA1 * m_valveResonY1[i]
                            + m_valveResonA2 * m_valveResonY2[i] + valveIn;
            m_valveResonY2[i] = m_valveResonY1[i];
            m_valveResonY1[i] = yV;

            // Knock click — DRY band-limited noise burst, no resonator ring.
            // m_knockBurstAmp[i] is the decaying envelope; m_knockResonY1[i]
            // is a one-pole LPF state colouring the noise to ~1.3 kHz. Each
            // knock is a tight click (~1.7ms) with NO reverb tail.
            //
            // Knock loudness follows a QUADRATIC rpm ramp (impact energy of
            // the piston hitting the valve ∝ velocity² ∝ rpm²). At idle it's
            // nearly silent; it comes up as the engine spins faster. The ramp
            // is dedicated (NOT attenuation_3, which saturates at ~382 rpm and
            // would make knock full-volume everywhere). Overall gain kept low
            // so knock is a faint layer UNDER the engine note, never dominant.
            double knockOut = 0.0;
            if (m_knockBurstAmp[i] > 1.0) {
                const double rawNoise = noise(m_audioRng);
                m_knockResonY1[i] = 0.74 * m_knockResonY1[i]
                                  + 0.26 * rawNoise;
                const double rpmRamp = std::min(1.0, rpm / kKnockFullRpm);
                const double knockRpmScale = rpmRamp * rpmRamp;
                knockOut = m_knockResonY1[i] * m_knockBurstAmp[i]
                         * 0.025 * knockRpmScale;
                m_knockBurstAmp[i] *= kKnockEnvDecay;
            }

            clankBus    += yR + yP + yV;   // dry: chunk debris (block resonators)
            damageAudio += knockOut;       // wet: knock stays on the exhaust path
        }

        // Bearing growl — filtered white noise, NOT a sine wave. Real worn
        // bearings make a low rumbling sound (broadband, ~50-200 Hz) from
        // metal-on-metal rolling contact, not a pure tone. We feed white
        // noise through two cascaded one-pole LPFs at ~180 Hz cutoff:
        //   y[n] = a·y[n-1] + (1-a)·x[n]
        // Two stages give a sharper cutoff and a more "throaty" feel.
        const double growlLevel = thermal->getBearingWhineLevel();
        if (growlLevel > 0.0) {
            constexpr double kGrowlCutoffHz = 180.0;
            const double a = std::exp(-kTwoPi * kGrowlCutoffHz / sampleRate);
            const double rawNoise = noise(m_audioRng);
            m_growlLP1 = a * m_growlLP1 + (1.0 - a) * rawNoise;
            m_growlLP2 = a * m_growlLP2 + (1.0 - a) * m_growlLP1;
            // Cascaded LPFs cut signal by ~20-30 dB; multiply by 10 to bring
            // amplitude back up to a usable range.
            damageAudio += growlLevel * rpmFactor
                         * kWhinePeak * 10.0 * m_growlLP2;
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

        // DRY catastrophe -> normalized to ~[-1,1], sent on the dry synthesizer
        // path that BYPASSES the reverberant exhaust convolution (no echo) and is
        // mixed at a known master-bus level. The BANG and the CLANKS are
        // normalized SEPARATELY so the bang reliably DOMINATES: the boom bus
        // saturates toward full scale (kBoomNorm below its peak), while the clank
        // bus is capped at kClankCatMax (< 1) so debris is always clearly quieter
        // than the bang. They rarely overlap; the sum is clamped for safety.
        constexpr double kBoomNorm    = 7.0e7;   // boom saturates HARD -> dense, loud
        constexpr double kClankNorm   = 1.8e8;
        constexpr double kClankCatMax = 0.7;     // debris ceiling (below the bang)
        const double catBoom  = std::tanh(boomBus / kBoomNorm);
        const double catClank = kClankCatMax * std::tanh(clankBus / kClankNorm);
        double cat = (catBoom + catClank) * rpmFactor;
        dryDamage = std::max(-1.0, std::min(1.0, cat));
    }

    synthesizer().writeInput(m_exhaustFlowStagingBuffer, dryDamage);
}
