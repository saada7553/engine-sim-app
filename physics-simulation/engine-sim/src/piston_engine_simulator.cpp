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

    m_whinePhase = 0.0;
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
    const double sampleRate = static_cast<double>(getSimulationFrequency());
    auto configureResonator = [&](double freq, double Q, double &a1, double &a2) {
        const double omega = 2.0 * constants::pi * freq / sampleRate;
        const double r = std::exp(-constants::pi * freq / (Q * sampleRate));
        a1 =  2.0 * r * std::cos(omega);
        a2 = -r * r;
    };

    // Knock primary mode: ~6 kHz Q=35 — rings ~30 ms.
    configureResonator(6000.0,  35.0, m_knockResonA1,  m_knockResonA2);
    // Knock secondary mode: ~9.3 kHz, lower Q. Inharmonic w.r.t. primary;
    // gives knock its metallic tinny character.
    configureResonator(9300.0,  22.0, m_knockReson2A1, m_knockReson2A2);
    // Rod knock: engine block fundamental. ~190 Hz Q=10 — sustains ~85 ms,
    // the characteristic deep "tock" of bearing slap.
    configureResonator(190.0,   10.0, m_rodResonA1,    m_rodResonA2);
    // Piston slap: second block mode. ~700 Hz Q=8 — higher-pitched body,
    // shorter ring (~25 ms). Sounds like a tick with body, not a click.
    configureResonator(700.0,    8.0, m_pistonResonA1, m_pistonResonA2);
    // Valve clatter: low-Q metallic tick. ~2.2 kHz Q=4 — very short ring
    // (~5 ms). At Q=4 the resonator sounds percussive (a "tick"), not tonal
    // (a "whistle"). Critical: when many of these fire together during a
    // moneyshift, the low Q prevents them from blending into a sustained
    // tone — they stay distinct clatter events.
    configureResonator(2200.0,   4.0, m_valveResonA1,  m_valveResonA2);
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
    constexpr int kKnockBurstSamples  = 32;
    constexpr int kRodBurstSamples    = 14;
    constexpr int kPistonBurstSamples = 12;
    constexpr int kValveBurstSamples  = 8;

    constexpr double kKnockExciteMax  = 2.5e8;
    constexpr double kRodExciteMax    = 8.0e6;   // peak output ~3e8 = subtle
    constexpr double kPistonExciteMax = 3.5e6;
    constexpr double kValveExciteMax  = 7.0e6;
    constexpr double kWhinePeak       = 2.0e6;

    // Gate damage audio on engine rotation (silent at zero RPM).
    const double rpmForAudio = m_engine->getRpm();
    const double rpmFactor = std::min(1.0,
        std::max(0.0, (rpmForAudio - 50.0) / 250.0));

    std::uniform_real_distribution<double> noise(-1.0, 1.0);

    // ===== PASS 1: Combustion-driven knock + per-cylinder exhaust pulses =====
    // Knock is the one damage sound that's genuinely combustion-driven (it IS
    // the chamber wall ringing from a detonation shock). It rides the per-
    // cylinder exhaust path, so it picks up the same delay-filter + impulse-
    // response acoustics as the exhaust pulse — physically correct.
    if (thermal != nullptr) {
        for (int i = 0; i < cylinderCount; ++i) {
            CombustionChamber *ch = m_engine->getChamber(i);
            if (ch->popLitLastFrame()) {
                const double knockExcite = thermal->sampleKnockImpulse(i);
                if (knockExcite > 0.0) {
                    m_knockBurstSamples[i] = kKnockBurstSamples;
                    m_knockBurstAmp[i] = knockExcite;
                }
            }
        }
    }

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

        // Knock: two parallel chamber-mode resonators, noise-burst excited.
        // No knock contribution from a dead cylinder either.
        double knockInput = 0.0;
        if (!dead && m_knockBurstSamples[i] > 0) {
            knockInput = noise(m_audioRng) * m_knockBurstAmp[i];
            m_knockBurstSamples[i]--;
        }
        {
            const double y0 = m_knockResonA1 * m_knockResonY1[i]
                            + m_knockResonA2 * m_knockResonY2[i] + knockInput;
            m_knockResonY2[i] = m_knockResonY1[i];
            m_knockResonY1[i] = y0;

            const double y0b = m_knockReson2A1 * m_knockReson2Y1[i]
                             + m_knockReson2A2 * m_knockReson2Y2[i]
                             + knockInput * 0.6;
            m_knockReson2Y2[i] = m_knockReson2Y1[i];
            m_knockReson2Y1[i] = y0b;
            exhaustFlow += cylAlive * (y0 + y0b);
        }

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

            // Crossing detection. cylAngle wraps 4π → 0 once per cycle.
            const bool crossedBDC_P =
                (lastAngle < kOnePi   && cylAngle >= kOnePi
                                      && cylAngle < kTwoPi);
            const bool crossedBDC_I =
                (lastAngle < kThreePi && cylAngle >= kThreePi
                                      && cylAngle < kFourPi);

            const bool dead = thermal->isCylinderDead(i);

            // ONLY valve clatter on cam events. Rod knock and piston slap
            // as event-driven resonators were the source of the persistent
            // "rattle" character — overlapping decaying sinusoids at every
            // firing accumulate into a busy texture that doesn't sound like
            // a real damaged engine. Those mechanical sounds are now
            // expressed through the bearing-whine continuous texture and
            // the dead-cylinder asymmetric exhaust note instead.
            if (!dead && (crossedBDC_P || crossedBDC_I)) {
                const double amp = thermal->getValveClatterLevel(i);
                if (amp > 0.0) {
                    m_valveBurstSamples[i] = kValveBurstSamples;
                    m_valveBurstAmp[i] = amp * kValveExciteMax;
                }
            }

            m_lastCylAngle[i] = cylAngle;
        }

        // Catastrophic event audio. Scales with engine size — a V12 grenade
        // is louder than an inline-4 grenade. Drives rod (190 Hz) + piston
        // (700 Hz) resonators only (no valve at 2.2 kHz — that whistled).
        // Attack is a few ms of noise burst; resonators ring it out as a
        // low-frequency mechanical thud over ~150 ms.
        if (thermal->popCatastrophicEvent()) {
            const double sizeFactor = std::sqrt(
                std::max(1.0, static_cast<double>(cylinderCount) / 4.0));
            for (int i = 0; i < cylinderCount; ++i) {
                m_rodBurstSamples[i] = kRodBurstSamples * 14;   // ~4 ms attack
                m_rodBurstAmp[i] = kRodExciteMax * 4.0 * sizeFactor;
                m_pistonBurstSamples[i] = kPistonBurstSamples * 12;
                m_pistonBurstAmp[i] = kPistonExciteMax * 3.0 * sizeFactor;
            }
        }

        // Step resonators and sum.
        // Rod and piston resonators are still stepped (in case catastrophic
        // events kick them) but they're no longer fired by per-cylinder
        // crank-angle crossings — that was the source of the persistent
        // rattle. Only the catastrophic event drives them, which is rare.
        double damageAudio = 0.0;
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

            damageAudio += yR + yP + yV;
        }

        // Bearing whine — subtle low-mid growl at 3× crank.
        const double whineLevel = thermal->getBearingWhineLevel();
        if (whineLevel > 0.0) {
            const double whineFreq = (rpm / 60.0) * 3.0;
            m_whinePhase += kTwoPi * whineFreq * timestep;
            if (m_whinePhase > kTwoPi) m_whinePhase -= kTwoPi;
            damageAudio += whineLevel * rpmFactor * kWhinePeak
                         * std::sin(m_whinePhase);
        }

        // Scale the entire damage layer by attenuation_3 (engine-load factor)
        // PLUS rpmFactor (rotation gate). The result: damage audio always
        // sits at a fraction of the current exhaust level. At idle the
        // exhaust pulses are small and so is the damage. Under load both
        // grow together. Damage is heard ON the engine, never INSTEAD of it.
        if (exhaustSystemCount > 0) {
            const double loadGate = attenuation_3 * rpmFactor;
            const double perChannel = damageAudio * loadGate
                                    / exhaustSystemCount;
            for (int j = 0; j < exhaustSystemCount; ++j) {
                m_exhaustFlowStagingBuffer[j] += perChannel;
            }
        }
    }

    synthesizer().writeInput(m_exhaustFlowStagingBuffer);
}
