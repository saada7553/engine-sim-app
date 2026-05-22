#ifndef ATG_ENGINE_SIM_PISTON_ENGINE_SIMULATOR_H
#define ATG_ENGINE_SIM_PISTON_ENGINE_SIMULATOR_H

#include "simulator.h"

#include "engine.h"
#include "transmission.h"
#include "combustion_chamber.h"
#include "vehicle.h"
#include "synthesizer.h"
#include "dynamometer.h"
#include "starter_motor.h"
#include "derivative_filter.h"
#include "vehicle_drag_constraint.h"
#include "delay_filter.h"

#include "scs.h"

#include <chrono>
#include <random>

class PistonEngineSimulator : public Simulator {
    public:
        PistonEngineSimulator();
        virtual ~PistonEngineSimulator() override;

        void loadSimulation(Engine *engine, Vehicle *vehicle, Transmission *transmission);

        virtual double getTotalExhaustFlow() const;
        void endFrame();
        virtual void destroy() override;

        void setFluidSimulationSteps(int steps) { m_fluidSimulationSteps = steps; }
        int getFluidSimulationSteps() const { return m_fluidSimulationSteps; }
        int getFluidSimulationFrequency() const { return m_fluidSimulationSteps * getSimulationFrequency(); }

        virtual double getAverageOutputSignal() const override;

        DerivativeFilter m_derivativeFilter;

    protected:
        virtual void simulateStep_() override;

    protected:
        void placeAndInitialize();
        void placeCylinder(int i);
        // Configure a 2-pole damped-resonator: y[n]=a1·y[n-1]+a2·y[n-2]+x[n].
        void configureResonator(double freq, double Q, double &a1, double &a2) const;

        // One money-shift impact = a SHAPED NOISE BURST (no tones — tones sound
        // like a piano). White noise through a 2-pole lowpass whose cutoff sweeps
        // DOWN over the hit: it starts as a broadband CRACK and decays into a low
        // combustion-like THUD, exactly like a loud backfire / explosion. Bigger
        // hits are deeper, louder and longer; small debris are sharp bright clacks.
        struct ImpactVoice {
            double env = 0.0, envDecay = 1.0;          // amplitude envelope
            double lp1 = 0.0, lp2 = 0.0;               // cascaded lowpass state
            double lpA = 0.0, lpAEnd = 0.0, lpACoef = 0.0; // swept cutoff (up=duller)
            double amp = 0.0;                          // makeup gain
            double crackAmp = 0.0;                     // broadband attack-edge level
            int    crackSamples = 0;
        };
        // fire = trigger one bang (scale 0..1 loudness, bigness 0=small tick ..
        // 1=huge bang); render = advance one voice a sample, returning its output.
        void fireImpactVoice(double scale, double bigness);
        double renderImpactVoice(ImpactVoice &v, double sampleRate);

    protected:
        virtual void writeToSynthesizer() override;

    protected:
        DelayFilter *m_delayFilters;

        atg_scs::FixedPositionConstraint *m_crankConstraints;
        atg_scs::ClutchConstraint *m_crankshaftLinks;
        atg_scs::RotationFrictionConstraint *m_crankshaftFrictionConstraints;
        atg_scs::LineConstraint *m_cylinderWallConstraints;
        atg_scs::LinkConstraint *m_linkConstraints;
        atg_scs::RigidBody m_vehicleMass;
        VehicleDragConstraint m_vehicleDrag;

        std::chrono::steady_clock::time_point m_simulationStart;
        std::chrono::steady_clock::time_point m_simulationEnd;

        Engine *m_engine;
        Transmission *m_transmission;
        Vehicle *m_vehicle;

        double *m_exhaustFlowStagingBuffer;

        int m_fluidSimulationSteps;

        // ---- Damage / thermal coupling ----
        // Previous crankshaft cycle angle for 4π wrap detection.
        double m_previousCycleAngle = 0.0;
        // Per-cylinder bent-valve clack envelope. The only fake-audio impulse
        // left for the top end; everything else rides on physics.
        double *m_bentValveEnvelope = nullptr;

        // ===== ROTATION-DRIVEN DAMAGE AUDIO =====
        // Damage sounds in real engines aren't gated on combustion — bearings
        // slap at TDC, pistons rock at BDC, bearings whine continuously with
        // RPM. Only knock is genuinely combustion-driven. The rest hang off
        // crankshaft angle and run independent of whether the spark fires.
        //
        // Architecture: per-cylinder crank-angle tracking detects TDC/BDC
        // crossings; each crossing kicks the appropriate resonator with a
        // short noise burst. Continuous textures (whine, block hum) run every
        // step regardless. The resonators' damped sinusoid impulse response
        // gives each impact its characteristic acoustic body.

        // Per-cylinder crank cycle position [0, 4π) on the last audio sample
        // — needed to detect when each cylinder rolls through TDC/BDC.
        double *m_lastCylAngle = nullptr;

        // --- Knock (combustion-driven, kept) ---
        // Chamber-wall ringing at 6 kHz + 9.3 kHz from detonation pressure
        // shocks. Multi-mode for metallic character. Noise-burst excited.
        double *m_knockResonY1 = nullptr;
        double *m_knockResonY2 = nullptr;
        double m_knockResonA1 = 0.0;
        double m_knockResonA2 = 0.0;
        double *m_knockReson2Y1 = nullptr;
        double *m_knockReson2Y2 = nullptr;
        double m_knockReson2A1 = 0.0;
        double m_knockReson2A2 = 0.0;
        int    *m_knockBurstSamples = nullptr;
        double *m_knockBurstAmp     = nullptr;

        // --- Bearing growl (continuous filtered noise) ---
        // Worn bearings make a low rumbling growl, not a whistle. Generated
        // by feeding white noise through two cascaded one-pole low-pass
        // filters tuned to ~180 Hz. Modulated by main-bearing damage + RPM.
        double m_growlLP1 = 0.0;
        double m_growlLP2 = 0.0;

        // --- Catastrophic event (money-shift grenade) ---
        // A money shift is modelled as a STOCHASTIC CHAIN OF IMPACTS: one big
        // initial BANG when something lets go, then a chaotic, decaying flurry of
        // secondary bangs as broken parts get flung around and ejected. Each bang
        // is a punchy IMPACT VOICE (sharp click + downward pitch-swept thump +
        // inharmonic metallic ring); a randomized point process schedules them.
        // Failure-type weights tilt impact pitch (rod/crank deep, valve/cam high).
        double m_catastropheSizeFactor   = 1.0;
        double m_catastropheRodWeight    = 1.0;
        double m_catastrophePistonWeight = 1.0;
        double m_catastropheValveWeight  = 1.0;

        static constexpr int kImpactVoices = 24;
        ImpactVoice m_impact[kImpactVoices] = {};
        int m_impactNext = 0;                          // round-robin voice index

        // Chaotic-debris scheduler.
        bool   m_crashActive    = false;
        double m_crashElapsed   = 0.0;   // s since the primary bang
        double m_crashDuration  = 0.0;   // s, randomized per event
        int    m_bounceCount    = 0;     // hits left in the current bounce cluster
        double m_bounceTimer    = 0.0;   // s until the next bounce hit
        double m_bounceInterval = 0.0;   // s between bounce hits (shrinks)
        double m_bounceAmp      = 0.0;   // bounce amplitude (shrinks)

        // RNG for noise bursts. Sim-thread only.
        std::mt19937 m_audioRng{0xC0DEBEEFu};
};

#endif /* ATG_ENGINE_SIM_PISTON_ENGINE_SIMULATOR_H */
