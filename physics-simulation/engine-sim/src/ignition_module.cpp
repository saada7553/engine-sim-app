#include "../include/ignition_module.h"

#include "../include/utilities.h"
#include "../include/constants.h"
#include "../include/units.h"

#include <cmath>
#include <algorithm>

namespace {
    // Bracket `v` within an ascending bin array, returning the low/high indices
    // and the interpolation fraction between them. Clamps at both ends.
    void bracketBins(double v, const double *bins, int n,
                     int &lo, int &hi, double &frac) {
        if (n <= 1 || v <= bins[0]) { lo = hi = 0; frac = 0.0; return; }
        if (v >= bins[n - 1]) { lo = hi = n - 1; frac = 0.0; return; }
        for (int i = 0; i < n - 1; ++i) {
            if (v >= bins[i] && v < bins[i + 1]) {
                lo = i; hi = i + 1;
                frac = (v - bins[i]) / (bins[i + 1] - bins[i]);
                return;
            }
        }
        lo = hi = n - 1; frac = 0.0;
    }
}

IgnitionModule::IgnitionModule() {
    m_plugs = nullptr;
    m_crankshaft = nullptr;
    m_timingCurve = nullptr;
    m_cylinderCount = 0;
    m_lastCrankshaftAngle = 0.0;
    m_enabled = false;
    m_revLimitTimer = 0.0;
    m_revLimit = 0;
    m_limiterDuration = 0;
}

IgnitionModule::~IgnitionModule() {
    assert(m_plugs == nullptr);
}

void IgnitionModule::destroy() {
    delete[] m_plugs;

    m_plugs = nullptr;
    m_cylinderCount = 0;
}

void IgnitionModule::initialize(const Parameters &params) {
    m_cylinderCount = params.cylinderCount;
    m_plugs = new SparkPlug[m_cylinderCount];
    m_crankshaft = params.crankshaft;
    m_timingCurve = params.timingCurve;
    m_revLimit = params.revLimit;
    m_limiterDuration = params.limiterDuration;
}

void IgnitionModule::setFiringOrder(int cylinderIndex, double angle) {
    assert(cylinderIndex < m_cylinderCount);

    m_plugs[cylinderIndex].angle = angle;
    m_plugs[cylinderIndex].enabled = true;
}

void IgnitionModule::reset() {
    m_lastCrankshaftAngle = m_crankshaft->getCycleAngle();
    resetIgnitionEvents();
}

void IgnitionModule::update(double dt) {
    const double cycleAngle = m_crankshaft->getCycleAngle();

    if (m_enabled && m_revLimitTimer == 0) {
        const double fourPi = 4 * constants::pi;
        const double advance = getTimingAdvance();

        for (int i = 0; i < m_cylinderCount; ++i) {
            double adjustedAngle = positiveMod(m_plugs[i].angle - advance, fourPi);
            const double r0 = m_lastCrankshaftAngle;
            double r1 = cycleAngle;

            if (m_crankshaft->m_body.v_theta < 0) {
                if (r1 < r0) {
                    r1 += fourPi;
                    adjustedAngle += fourPi;
                }

                if (adjustedAngle >= r0 && adjustedAngle < r1) {
                    m_plugs[i].ignitionEvent = m_plugs[i].enabled;
                }
            }
            else {
                if (r1 > r0) {
                    r1 -= fourPi;
                    adjustedAngle -= fourPi;
                }

                if (adjustedAngle >= r1 && adjustedAngle < r0) {
                    m_plugs[i].ignitionEvent = m_plugs[i].enabled;
                }
            }
        }
    }

    m_revLimitTimer -= dt;
    if (std::fabs(m_crankshaft->m_body.v_theta) > m_revLimit) {
        m_revLimitTimer = m_limiterDuration;
    }

    if (m_revLimitTimer < 0) {
        m_revLimitTimer = 0;
    }

    m_lastCrankshaftAngle = cycleAngle;
}

bool IgnitionModule::getIgnitionEvent(int index) const {
    return m_plugs[index].ignitionEvent;
}

void IgnitionModule::resetIgnitionEvents() {
    for (int i = 0; i < m_cylinderCount; ++i) {
        m_plugs[i].ignitionEvent = false;
    }
}

void IgnitionModule::setPlugEnabled(int cylinderIndex, bool enabled) {
    if (cylinderIndex < 0 || cylinderIndex >= m_cylinderCount) return;
    m_plugs[cylinderIndex].enabled = enabled;
}

bool IgnitionModule::isPlugEnabled(int cylinderIndex) const {
    if (cylinderIndex < 0 || cylinderIndex >= m_cylinderCount) return false;
    return m_plugs[cylinderIndex].enabled;
}

double IgnitionModule::getTimingAdvance() {
    const double w = -m_crankshaft->m_body.v_theta;
    const double load = m_mapCurrentLoad.load(std::memory_order_relaxed);
    double base;
    {
        std::lock_guard<std::mutex> lock(m_mapMutex);
        base = m_hasTimingMap
            ? sampleTimingMap(w, load)
            : m_timingCurve->sampleTriangle(w);
    }
    return base + m_ignitionOffset;
}

double IgnitionModule::getTimingAdvanceForRpm(double rpm) {
    // Pure base curve — kept stable so the Swift ECU model can seed its cells
    // and compute deviations against the engine's stock timing.
    return m_timingCurve->sampleTriangle(units::rpm(rpm));
}

double IgnitionModule::getTunedAdvanceForRpm(double rpm) {
    const double w = units::rpm(rpm);
    const double load = m_mapCurrentLoad.load(std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(m_mapMutex);
    return m_hasTimingMap
        ? sampleTimingMap(w, load)
        : m_timingCurve->sampleTriangle(w);
}

void IgnitionModule::setTimingMap(const double *wBins, int nW,
                                  const double *loadBins, int nLoad,
                                  const double *advRad) {
    std::lock_guard<std::mutex> lock(m_mapMutex);
    if (nW <= 0 || nLoad <= 0) { m_hasTimingMap = false; return; }
    const int cw = std::min(nW, MaxMapRpmBins);
    const int cl = std::min(nLoad, MaxMapLoadBins);
    for (int i = 0; i < cw; ++i) m_mapW[i] = wBins[i];
    for (int j = 0; j < cl; ++j) m_mapLoad[j] = loadBins[j];
    // Source is row-major with stride nW; our buffer uses stride MaxMapRpmBins.
    for (int j = 0; j < cl; ++j) {
        for (int i = 0; i < cw; ++i) {
            m_mapAdv[j * MaxMapRpmBins + i] = advRad[j * nW + i];
        }
    }
    m_mapRpmCount = cw;
    m_mapLoadCount = cl;
    m_hasTimingMap = true;
}

// Caller must hold m_mapMutex.
double IgnitionModule::sampleTimingMap(double w, double loadKpa) const {
    int xl, xh, yl, yh;
    double xf, yf;
    bracketBins(w, m_mapW, m_mapRpmCount, xl, xh, xf);
    bracketBins(loadKpa, m_mapLoad, m_mapLoadCount, yl, yh, yf);
    const double v00 = m_mapAdv[yl * MaxMapRpmBins + xl];
    const double v10 = m_mapAdv[yl * MaxMapRpmBins + xh];
    const double v01 = m_mapAdv[yh * MaxMapRpmBins + xl];
    const double v11 = m_mapAdv[yh * MaxMapRpmBins + xh];
    const double v0 = v00 + xf * (v10 - v00);
    const double v1 = v01 + xf * (v11 - v01);
    return v0 + yf * (v1 - v0);
}

IgnitionModule::SparkPlug *IgnitionModule::getPlug(int i) {
    return &m_plugs[((i % m_cylinderCount) + m_cylinderCount) % m_cylinderCount];
}
