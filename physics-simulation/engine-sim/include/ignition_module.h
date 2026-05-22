#ifndef ATG_ENGINE_SIM_IGNITION_MODULE_H
#define ATG_ENGINE_SIM_IGNITION_MODULE_H

#include "part.h"

#include "crankshaft.h"
#include "function.h"
#include "units.h"

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

        bool m_enabled;
        double m_ignitionOffset = 0.0;

    protected:
        SparkPlug *getPlug(int i);

        Function *m_timingCurve;
        SparkPlug *m_plugs;
        Crankshaft *m_crankshaft;
        int m_cylinderCount;

        double m_lastCrankshaftAngle;
        double m_revLimit;
        double m_revLimitTimer;
        double m_limiterDuration;
};

#endif /* ATG_ENGINE_SIM_IGNITION_MODULE_H */
