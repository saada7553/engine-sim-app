#ifndef ATG_ENGINE_SIM_IGNITION_MODULE_H
#define ATG_ENGINE_SIM_IGNITION_MODULE_H

#include "part.h"

#include "crankshaft.h"
#include "function.h"
#include "units.h"

#include <mutex>
#include <atomic>

class IgnitionModule : public Part {
    public:
        struct Parameters {
            int cylinderCount;
            Crankshaft *crankshaft;
            Function *timingCurve;
            double revLimit = units::rpm(6000.0);
            double limiterDuration = 0.5 * units::sec;
        };

        struct SparkPlug {
            double angle = 0;
            bool ignitionEvent = false;
            bool enabled = false;
        };

    public:
        IgnitionModule();
        virtual ~IgnitionModule();

        virtual void destroy();

        void initialize(const Parameters &params);
        void setFiringOrder(int cylinderIndex, double angle);
        void reset();
        void update(double dt);

        bool getIgnitionEvent(int index) const;
        void resetIgnitionEvents();

        /// Per-cylinder spark control. Disabling a plug stops it from firing,
        /// so that cylinder draws in its charge and pumps it out unburnt — the
        /// equivalent of pulling a single coil wire. Out-of-range indices are
        /// ignored / reported disabled.
        void setPlugEnabled(int cylinderIndex, bool enabled);
        bool isPlugEnabled(int cylinderIndex) const;
        int getCylinderCount() const { return m_cylinderCount; }

        /// Per-cylinder firing angle in the 4-stroke cycle, in radians [0, 4π).
        /// Combined with the output crankshaft's current cycle angle this
        /// gives the position of each cylinder in its own cycle — needed for
        /// rotation-driven damage audio (rod knock at TDC compression, etc.).
        double getFiringAngle(int cylinderIndex) const {
            return m_plugs[cylinderIndex].angle;
        }

        double getTimingAdvance();
        double getTimingAdvanceForRpm(double rpm);

        /// Rev limiter ceiling in rad/s (same units as Engine::getRedline).
        /// The engine can't exceed this under its own power, so it's the
        /// reference point for over-rev / valve-float damage rather than the
        /// redline (which sits below normal limiter operation).
        double getRevLimit() const { return m_revLimit; }

        // ECU timing map (2D: angular-velocity × load). When set, it replaces
        // the engine's built-in base timing curve so an edited tune genuinely
        // reshapes the spark advance per rpm AND load, instead of the old
        // single scalar offset that could only translate the curve. The scalar
        // m_ignitionOffset rides on top for the live "chaos surge".
        //
        // The physics thread reads this map every substep while the UI thread
        // overwrites it on edits, so the map buffers + their counts + the
        // `m_hasTimingMap` flag are guarded by `m_mapMutex` to give the reader
        // a consistent snapshot. Map writes are rare (only on a tune edit) and
        // the critical section is a handful of array reads, so the lock is
        // effectively free on the hot path. The per-tick current-load value is
        // a single scalar updated far more often, so it stays a lock-free
        // atomic instead of taking the lock every frame.
        static constexpr int MaxMapRpmBins = 16;
        static constexpr int MaxMapLoadBins = 8;
        void setTimingMap(const double *wBins, int nW,
                          const double *loadBins, int nLoad,
                          const double *advRad);
        void clearTimingMap() {
            std::lock_guard<std::mutex> lock(m_mapMutex);
            m_hasTimingMap = false;
        }
        void setCurrentLoad(double loadKpa) {
            m_mapCurrentLoad.store(loadKpa, std::memory_order_relaxed);
        }
        /// Map-aware advance at an rpm (current load), or the base curve when no
        /// map is set. Used by the spark-advance scope and physics; distinct
        /// from getTimingAdvanceForRpm, which stays the pure base curve so it
        /// can keep seeding the Swift ECU model.
        double getTunedAdvanceForRpm(double rpm);

        bool m_enabled;
        double m_ignitionOffset = 0.0;

    protected:
        SparkPlug *getPlug(int i);

        double sampleTimingMap(double w, double loadKpa) const;

        Function *m_timingCurve;
        SparkPlug *m_plugs;
        Crankshaft *m_crankshaft;
        int m_cylinderCount;

        double m_lastCrankshaftAngle;
        double m_revLimit;
        double m_revLimitTimer;
        double m_limiterDuration;

        mutable std::mutex m_mapMutex;                          // guards the map buffers below
        bool m_hasTimingMap = false;
        int m_mapRpmCount = 0;
        int m_mapLoadCount = 0;
        double m_mapW[MaxMapRpmBins] = {0};                     // rad/s, ascending
        double m_mapLoad[MaxMapLoadBins] = {0};                 // kPa, ascending
        double m_mapAdv[MaxMapLoadBins * MaxMapRpmBins] = {0};  // rad, row-major [load][w]
        std::atomic<double> m_mapCurrentLoad{0.0};              // kPa; lock-free (written every tick)
};

#endif /* ATG_ENGINE_SIM_IGNITION_MODULE_H */
