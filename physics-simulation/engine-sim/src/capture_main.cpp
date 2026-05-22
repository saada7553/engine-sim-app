// TEST-ONLY headless harness: spin the engine, force a catastrophe, capture
// the synthesizer output to /tmp/cap.pcm (raw mono int16) for offline analysis.
#include "../include/transmission.h"
#include "../scripting/include/compiler.h"
#include "../include/s_audio_file.h"
#include "../include/engine.h"
#include "../include/simulator.h"
#include "../include/synthesizer.h"
#include "../include/thermal_system.h"

#include <cstdio>
#include <vector>
#include <cstdint>
#include <unistd.h>

int main(int argc, char **argv) {
    es_script::Compiler compiler;
    compiler.initialize();
    const char *script = (argc > 1) ? argv[1] : "../assets/test_flat4_builder.mr";
    const double holdRpm = (argc > 2) ? atof(argv[2]) : 4500.0;
    if (!compiler.compile(script)) { printf("compile fail: %s\n", script); return 1; }
    auto out = compiler.execute();
    Engine *engine = out.engine;
    Vehicle *vehicle = out.vehicle;
    Transmission *transmission = out.transmission;
    compiler.destroy();
    if (!engine) { printf("no engine\n"); return 1; }

    if (!vehicle) {
        Vehicle::Parameters vp;
        vp.mass = units::mass(1597, units::kg);
        vp.diffRatio = 3.42;
        vp.tireRadius = units::distance(10, units::inch);
        vp.dragCoefficient = 0.25;
        vp.crossSectionArea = units::distance(6.0, units::foot) * units::distance(6.0, units::foot);
        vp.rollingResistance = 2000.0;
        vehicle = new Vehicle;
        vehicle->initialize(vp);
    }

    Simulator *sim = engine->createSimulator(vehicle, transmission);
    sim->getEngine()->getIgnitionModule()->m_enabled = true;
    sim->m_starterMotor.m_enabled = false;
    // Hold the engine at a fixed high RPM with the dyno so combustion/exhaust
    // audio is guaranteed (the test engine won't self-idle headless).
    sim->m_dyno.m_enabled = true;
    sim->m_dyno.m_hold = true;
    sim->m_dyno.m_rotationSpeed = units::rpm(holdRpm);
    engine->calculateDisplacement();
    sim->setSimulationSpeed(1.0);
    sim->setSimulationFrequency(engine->getSimulationFrequency());

    Synthesizer::AudioParameters ap = sim->synthesizer().getAudioParameters();
    ap.inputSampleNoise = (float)engine->getInitialJitter();
    ap.airNoise = (float)engine->getInitialNoise();
    ap.dF_F_mix = (float)engine->getInitialHighFrequencyGain();
    sim->synthesizer().setAudioParameters(ap);

    for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
        ImpulseResponse *resp = engine->getExhaustSystem(i)->getImpulseResponse();
        sAudioFile wf;
        if (wf.OpenFile(resp->getFilename().c_str()) != sAudioFile::Error::None) continue;
        wf.InitializeInternalBuffer(wf.GetSampleCount());
        wf.FillBuffer(0);
        wf.CloseFile();
        sim->synthesizer().initializeImpulseResponse(
            (const int16_t *)wf.GetBuffer(), wf.GetSampleCount(), resp->getVolume(), i);
        wf.DestroyInternalBuffer();
    }

    sim->startAudioRenderingThread();

    std::vector<int16_t> cap;
    int16_t tmp[4096];
    double throttle = 0.0;
    bool forced = false;
    long forcedSample = -1;
    const double frameDt = 1.0 / 120.0;

    const int totalFrames = (int)(6.0 / frameDt);
    for (int f = 0; f < totalFrames; ++f) {
        const double t = f * frameDt;
        const double rpm = engine->getRpm();
        throttle = 0.9;
        engine->setSpeedControl(throttle);
        if (transmission) sim->getTransmission()->setClutchPressure(0.0); // neutral
        sim->m_dyno.m_rotationSpeed = units::rpm(holdRpm);
        // Force the catastrophe once the engine is actually spinning.
        if (!forced && rpm > 1500.0 && t > 1.0) {
            engine->getThermalSystem()->debugForceCatastrophe();
            forced = true;
            forcedSample = (long)cap.size();
            printf("FORCED catastrophe at t=%.2f rpm=%.0f sample=%ld\n",
                   t, rpm, forcedSample);
        }
        sim->startFrame(frameDt);
        while (sim->simulateStep()) {}
        sim->endFrame();

        int got;
        do {
            got = sim->synthesizer().readAudioOutput(4096, tmp);
            for (int i = 0; i < got; ++i) cap.push_back(tmp[i]);
        } while (got == 4096);

        usleep((useconds_t)(frameDt * 1e6 * 0.5));  // let render thread keep pace
        if (f % 60 == 0)
            printf("t=%.2f rpm=%.0f cap=%zu\n", t, engine->getRpm(), cap.size());
    }

    sim->endAudioRenderingThread();

    FILE *fp = fopen("/tmp/cap.pcm", "wb");
    fwrite(cap.data(), 2, cap.size(), fp);
    fclose(fp);
    printf("wrote %zu samples, forcedSample=%ld\n", cap.size(), forcedSample);
    return 0;
}
