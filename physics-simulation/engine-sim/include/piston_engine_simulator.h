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

        // --- Rod knock (rotation-driven) ---
        // Bearing journal slap on TDC crossings. Block fundamental mode.
        double *m_rodResonY1 = nullptr;
        double *m_rodResonY2 = nullptr;
        double m_rodResonA1 = 0.0;
        double m_rodResonA2 = 0.0;
        int    *m_rodBurstSamples = nullptr;
        double *m_rodBurstAmp     = nullptr;

        // --- Piston slap (rotation-driven) ---
        // Piston rocks in the bore at velocity reversals. Higher-pitched body
        // resonance than rod knock — second block mode.
        double *m_pistonResonY1 = nullptr;
        double *m_pistonResonY2 = nullptr;
        double m_pistonResonA1 = 0.0;
        double m_pistonResonA2 = 0.0;
        int    *m_pistonBurstSamples = nullptr;
        double *m_pistonBurstAmp     = nullptr;

        // --- Valve clatter (rotation-driven) ---
        // Bent/worn valves click against their seats at every cam event.
        // Higher-frequency mid-band ring — metallic but not as bright as knock.
        double *m_valveResonY1 = nullptr;
        double *m_valveResonY2 = nullptr;
        double m_valveResonA1 = 0.0;
        double m_valveResonA2 = 0.0;
        int    *m_valveBurstSamples = nullptr;
        double *m_valveBurstAmp     = nullptr;

        // --- Bearing growl (continuous filtered noise) ---
        // Worn bearings make a low rumbling growl, not a whistle. Generated
        // by feeding white noise through two cascaded one-pole low-pass
        // filters tuned to ~180 Hz. Modulated by main-bearing damage + RPM.
        double m_growlLP1 = 0.0;
        double m_growlLP2 = 0.0;

        // --- Catastrophic event state ---
        // A moneyshift catastrophe fires the BOOM + CLANK synthesizer below. The
        // per-failure-type weights tilt the clank pitch (a valve-drop clanks
        // higher/brighter than a rod-eject).
        double m_catastropheSizeFactor = 1.0;
        double m_catastropheRodWeight    = 1.0;
        double m_catastrophePistonWeight = 1.0;
        double m_catastropheValveWeight  = 1.0;

        // --- The BOOM (initial detonation) ---
        // Audible-band (~110-170 Hz) resonator driven by a short NOISE burst
        // (m_boomBurst samples at m_boomBurstAmp) for a punchy thud + harmonics,
        // plus a brief broadband CLICK (m_boomClickSamples at m_boomClickAmp) for
        // the sharp detonation crack. ~110-170 Hz so it survives speaker rolloff.
        double m_boomY1 = 0.0;
        double m_boomY2 = 0.0;
        double m_boomA1 = 0.0;
        double m_boomA2 = 0.0;
        int    m_boomBurst       = 0;     // low-body resonator excitation samples
        double m_boomBurstAmp    = 0.0;
        // Explosive BLAST: a short, fast-decaying broadband noise burst (the
        // sharp "crack" of the detonation) — this is what makes it read as a
        // BANG rather than a pure low tone. m_boomBlastAmp decays each sample.
        int    m_boomBlastSamples = 0;
        double m_boomBlastAmp     = 0.0;
        double m_boomBlastLP      = 0.0;

        // --- The DEBRIS (parts breaking apart) ---
        // Two ingredients fired by a decaying-rate event window:
        //   1. Original-style metallic IMPACTS: the per-cylinder rod/piston/valve
        //      block resonators + a short grind-noise burst (m_grindLP*).
        //   2. MINI-BOOMS: occasional quieter, cleaner versions of the main bang
        //      — low-frequency thumps voiced through the resonator pool below.
        double m_grindLP1 = 0.0;   // grind-noise amplitude (decays per impact)
        double m_grindLP2 = 0.0;
        double m_grindLP3 = 0.0;
        static constexpr int kCrashVoices = 14;
        double m_crashVY1[kCrashVoices] = {};
        double m_crashVY2[kCrashVoices] = {};
        double m_crashVA1[kCrashVoices] = {};
        double m_crashVA2[kCrashVoices] = {};
        int    m_crashVBurst[kCrashVoices] = {};    // remaining excitation samples
        double m_crashVBurstAmp[kCrashVoices] = {}; // excitation amplitude
        int    m_crashVoiceNext = 0;                // round-robin voice index
        int    m_clankCountdown  = 0;   // samples until the next clank
        int    m_clanksRemaining = 0;   // clanks left to fire this event
        int    m_clankTotal      = 1;   // total clanks this event (for settling)
        double m_clankAmp        = 0.0; // per-event peak clank amplitude

        // --- Block hum (deprecated, kept to avoid header churn) ---
        double m_blockHumY1 = 0.0;
        double m_blockHumY2 = 0.0;
        double m_blockHumA1 = 0.0;
        double m_blockHumA2 = 0.0;

        // RNG for noise bursts. Sim-thread only.
        std::mt19937 m_audioRng{0xC0DEBEEFu};
};

#endif /* ATG_ENGINE_SIM_PISTON_ENGINE_SIMULATOR_H */
