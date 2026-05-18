#include "../include/oscilloscope_cluster.h"
#include <sstream>

OscilloscopeCluster::OscilloscopeCluster() {
    m_simulator = nullptr;
    m_torqueScope = nullptr;
    m_powerScope = nullptr;
    m_totalExhaustFlowScope = nullptr;
    m_intakeFlowScope = nullptr;
    m_exhaustFlowScope = nullptr;
    m_exhaustValveLiftScope = nullptr;
    m_intakeValveLiftScope = nullptr;
    m_audioWaveformScope = nullptr;
    m_cylinderPressureScope = nullptr;
    m_sparkAdvanceScope = nullptr;
    m_cylinderMoleculesScope = nullptr;
    m_pvScope = nullptr;

    for (int i = 0; i < MaxLayeredScopes; ++i) {
        m_currentFocusScopes[i] = nullptr;
    }

    m_torque = 0;
    m_power = 0;

    m_updatePeriod = 0.25f;
    m_updateTimer = 0.0f;
    m_dynoWasSweeping = false;
}

OscilloscopeCluster::~OscilloscopeCluster() {
    /* void */
}

void OscilloscopeCluster::initialize() {
    m_torqueScope = new Oscilloscope;
    m_powerScope = new Oscilloscope;
    m_exhaustFlowScope = new Oscilloscope;
    m_totalExhaustFlowScope = new Oscilloscope;
    m_intakeFlowScope = new Oscilloscope;
    m_audioWaveformScope = new Oscilloscope;
    m_intakeValveLiftScope = new Oscilloscope;
    m_exhaustValveLiftScope = new Oscilloscope;
    m_cylinderPressureScope = new Oscilloscope;
    m_sparkAdvanceScope = new Oscilloscope;
    m_cylinderMoleculesScope = new Oscilloscope;
    m_pvScope = new Oscilloscope;


    // Torque
    m_torqueScope->setBufferSize(100);
    m_torqueScope->m_xMin = 0.0f;
    m_torqueScope->m_yMin = 0.0f;
    m_torqueScope->m_yMax = 0.0f;
    m_torqueScope->m_lineWidth = 2.0f;
    m_torqueScope->m_drawReverse = false;
    // X max is set explicitly to the last sampled RPM so the curve ends flush
    // with the right edge instead of leaving the resize headroom as a gap.
    m_torqueScope->m_dynamicallyResizeX = false;

    // Power
    m_powerScope->setBufferSize(100);
    m_powerScope->m_xMin = 0.0f;
    m_powerScope->m_yMin = 0.0f;
    m_powerScope->m_yMax = 0.0f;
    m_powerScope->m_lineWidth = 2.0f;
    m_powerScope->m_drawReverse = false;
    m_powerScope->m_dynamicallyResizeX = false;

    // Total exhaust flow
    m_totalExhaustFlowScope->setBufferSize(1024);
    m_totalExhaustFlowScope->m_xMin = 0.0f;
    m_totalExhaustFlowScope->m_xMax = constants::pi * 4;
    m_totalExhaustFlowScope->m_yMin = -units::flow(10, units::scfm);
    m_totalExhaustFlowScope->m_yMax = units::flow(10, units::scfm);
    m_totalExhaustFlowScope->m_lineWidth = 2.0f;
    m_totalExhaustFlowScope->m_drawReverse = false;

    // Exhaust flow
    m_exhaustFlowScope->setBufferSize(1024);
    m_exhaustFlowScope->m_xMin = 0.0f;
    m_exhaustFlowScope->m_xMax = constants::pi * 4;
    m_exhaustFlowScope->m_yMin = -units::flow(10.0, units::scfm);
    m_exhaustFlowScope->m_yMax = units::flow(10.0, units::scfm);
    m_exhaustFlowScope->m_lineWidth = 2.0f;
    m_exhaustFlowScope->m_drawReverse = false;

    // Intake flow
    m_intakeFlowScope->setBufferSize(1024);
    m_intakeFlowScope->m_xMin = 0.0f;
    m_intakeFlowScope->m_xMax = constants::pi * 4;
    m_intakeFlowScope->m_yMin = -units::flow(10.0, units::scfm);
    m_intakeFlowScope->m_yMax = units::flow(10.0, units::scfm);
    m_intakeFlowScope->m_lineWidth = 2.0f;
    m_intakeFlowScope->m_drawReverse = false;

    // Cylinder molcules
    m_cylinderMoleculesScope->setBufferSize(1024);
    m_cylinderMoleculesScope->m_xMin = 0.0f;
    m_cylinderMoleculesScope->m_xMax = constants::pi * 4;
    m_cylinderMoleculesScope->m_yMin = -0.05;
    m_cylinderMoleculesScope->m_yMax = 0.2;
    m_cylinderMoleculesScope->m_lineWidth = 4.0f;
    m_cylinderMoleculesScope->m_drawReverse = false;

    // Audio waveform scope
    m_audioWaveformScope->setBufferSize(44100 / 50);
    m_audioWaveformScope->m_xMin = 0.0f;
    m_audioWaveformScope->m_xMax = 44100 / 10;
    m_audioWaveformScope->m_yMin = -1.5f;
    m_audioWaveformScope->m_yMax = 1.5f;
    m_audioWaveformScope->m_lineWidth = 2.0f;
    m_audioWaveformScope->m_drawReverse = false;

    // Valve lift scopes
    m_exhaustValveLiftScope->setBufferSize(1024);
    m_exhaustValveLiftScope->m_xMin = 0.0f;
    m_exhaustValveLiftScope->m_xMax = constants::pi * 4;
    m_exhaustValveLiftScope->m_yMin = (float)units::distance(-10, units::thou);
    m_exhaustValveLiftScope->m_yMax = (float)units::distance(10, units::thou);
    m_exhaustValveLiftScope->m_lineWidth = 2.0f;
    m_exhaustValveLiftScope->m_drawReverse = false;

    m_intakeValveLiftScope->setBufferSize(1024);
    m_intakeValveLiftScope->m_xMin = 0.0f;
    m_intakeValveLiftScope->m_xMax = constants::pi * 4;
    m_intakeValveLiftScope->m_yMin = (float)units::distance(-10, units::thou);
    m_intakeValveLiftScope->m_yMax = (float)units::distance(10, units::thou);
    m_intakeValveLiftScope->m_lineWidth = 2.0f;
    m_intakeValveLiftScope->m_drawReverse = false;

    // Cylinder pressure scope
    m_cylinderPressureScope->setBufferSize(1024);
    m_cylinderPressureScope->m_xMin = 0.0f;
    m_cylinderPressureScope->m_xMax = constants::pi * 4;
    m_cylinderPressureScope->m_yMin = -(float)std::sqrt(units::pressure(1, units::psi));
    m_cylinderPressureScope->m_yMax = (float)std::sqrt(units::pressure(1, units::psi));
    m_cylinderPressureScope->m_lineWidth = 2.0f;
    m_cylinderPressureScope->m_drawReverse = false;

    // Pressure volume scope
    m_pvScope->setBufferSize(1024);
    m_pvScope->m_xMin = 0.0f;
    m_pvScope->m_xMax = units::volume(0.1, units::L);
    m_pvScope->m_yMin = -(float)std::sqrt(units::pressure(1, units::psi));
    m_pvScope->m_yMax = (float)std::sqrt(units::pressure(1, units::psi));
    m_pvScope->m_lineWidth = 2.0f;
    m_pvScope->m_drawReverse = true;
    m_pvScope->m_dynamicallyResizeX = true;

    // Spark advance scope
    m_sparkAdvanceScope->setBufferSize(1024);
    m_sparkAdvanceScope->m_xMin = 0.0f;
    m_sparkAdvanceScope->m_xMax = units::rpm(10000);
    m_sparkAdvanceScope->m_yMin = -units::angle(30, units::deg);
    m_sparkAdvanceScope->m_yMax = units::angle(60, units::deg);
    m_sparkAdvanceScope->m_lineWidth = 2.0f;
    m_sparkAdvanceScope->m_drawReverse = true;

    m_currentFocusScopes[0] = m_totalExhaustFlowScope;
    m_currentFocusScopes[1] = nullptr;

    m_torqueUnits = "lb/ft todo fix";
    m_powerUnits = "hp todo fix";
}

void OscilloscopeCluster::resetDynoScopes() {
    m_torqueScope->reset();
    m_powerScope->reset();
    m_torqueScope->m_xMin = m_torqueScope->m_xMax = 0.0;
    m_torqueScope->m_yMin = m_torqueScope->m_yMax = 0.0;
    m_powerScope->m_xMin = m_powerScope->m_xMax = 0.0;
    m_powerScope->m_yMin = m_powerScope->m_yMax = 0.0;
}

void OscilloscopeCluster::sample() {
    Engine *engine = m_simulator->getEngine();
    if (engine == nullptr) return;

    const double cylinderPressure = engine->getChamber(0)->m_system.pressure()
        + engine->getChamber(0)->m_system.dynamicPressure(-1.0, 0.0);

    if (m_simulator->getCurrentIteration() % 2 == 0) {
        double cycleAngle = engine->getCrankshaft(0)->getCycleAngle();
        if (!engine->isSpinningCw()) {
            cycleAngle = 4 * constants::pi - cycleAngle;
        }

        getTotalExhaustFlowOscilloscope()->addDataPoint(
            cycleAngle,
            m_simulator->getTotalExhaustFlow() / m_simulator->getTimestep());
        getCylinderPressureScope()->addDataPoint(
            engine->getCrankshaft(0)->getCycleAngle(constants::pi),
            std::sqrt(cylinderPressure));
        getExhaustFlowOscilloscope()->addDataPoint(
            cycleAngle,
            engine->getChamber(0)->getLastTimestepExhaustFlow() / m_simulator->getTimestep());
        getIntakeFlowOscilloscope()->addDataPoint(
            cycleAngle,
            engine->getChamber(0)->getLastTimestepIntakeFlow() / m_simulator->getTimestep());
        getCylinderMoleculesScope()->addDataPoint(
            cycleAngle,
            engine->getChamber(0)->m_system.n());
        getExhaustValveLiftOscilloscope()->addDataPoint(
            cycleAngle,
            engine->getChamber(0)->getCylinderHead()->exhaustValveLift(
                engine->getChamber(0)->getPiston()->getCylinderIndex()));
        getIntakeValveLiftOscilloscope()->addDataPoint(
            cycleAngle,
            engine->getChamber(0)->getCylinderHead()->intakeValveLift(
                engine->getChamber(0)->getPiston()->getCylinderIndex()));
        getPvScope()->addDataPoint(
            engine->getChamber(0)->getVolume(),
            std::sqrt(engine->getChamber(0)->m_system.pressure()));
    }

    // Dyno torque & power curve. The scopes are reset when a new sweep starts,
    // then sampled periodically for the duration of the sweep. Torque and power
    // keep independent axes, so their bounds are not synced together.
    const bool sweeping = m_simulator->m_dyno.m_enabled;
    if (sweeping && !m_dynoWasSweeping) {
        resetDynoScopes();
        m_updateTimer = m_updatePeriod;
    }
    m_dynoWasSweeping = sweeping;

    m_updateTimer += static_cast<float>(m_simulator->getTimestep());
    if (sweeping && m_updateTimer >= m_updatePeriod) {
        m_updateTimer = 0.0f;
        const double rpm = units::toRpm(engine->getSpeed());
        m_torqueScope->addDataPoint(rpm, m_simulator->getFilteredDynoTorque());
        m_powerScope->addDataPoint(rpm, m_simulator->getDynoPower() / 1000.0);
        m_torqueScope->m_xMax = m_powerScope->m_xMax = rpm;
    }

    m_exhaustFlowScope->m_yMin = m_intakeFlowScope->m_yMin =
        std::fmin(m_intakeFlowScope->m_yMin, m_exhaustFlowScope->m_yMin);
    m_exhaustFlowScope->m_yMax = m_intakeFlowScope->m_yMax =
        std::fmax(m_intakeFlowScope->m_yMax, m_exhaustFlowScope->m_yMax);
}

void OscilloscopeCluster::setSimulator(Simulator *simulator) {
    m_simulator = simulator;
}