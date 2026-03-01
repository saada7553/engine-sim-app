#include "../include/oscilloscope.h"
#include <cstdlib>

Oscilloscope::Oscilloscope() {
    m_xMin = m_xMax = 0;
    m_yMin = m_yMax = 0;
    m_lineWidth = 1;

    m_points = nullptr;
    m_writeIndex = 0;
    m_bufferSize = 0;
    m_pointCount = 0;
    m_drawReverse = true;
    m_drawZero = true;
    m_dynamicallyResizeX = false;
    m_dynamicallyResizeY = true;
}

Oscilloscope::~Oscilloscope() {}

void Oscilloscope::destroy() {
    delete[] m_points;
    m_points = nullptr;

    m_writeIndex = 0;
    m_bufferSize = 0;
    m_pointCount = 0;
}

void Oscilloscope::addDataPoint(double x, double y) {
    m_points[m_writeIndex] = { x, y };
    m_writeIndex = (m_writeIndex + 1) % m_bufferSize;
    m_pointCount = (m_pointCount >= m_bufferSize)
        ? m_bufferSize
        : m_pointCount + 1;

    if (m_dynamicallyResizeY) {
        if (y + std::abs(0.1 * y) >= m_yMax) {
            m_yMax = y + std::abs(0.1 * y);
        }
        else if (y - std::abs(0.1 * y) <= m_yMin) {
            m_yMin = y - std::abs(0.1 * y);
        }
    }
    if (m_dynamicallyResizeX) {
        if (x + std::abs(0.1 * x) >= m_xMax) {
            m_xMax = x + std::abs(0.1 * x);
        }
        else if (x - std::abs(0.1 * x) <= m_xMin) {
            m_xMin = x - std::abs(0.1 * x);
        }
    }
}

void Oscilloscope::setBufferSize(int n) {
    m_points = new DataPoint[n];
    m_bufferSize = n;
    reset();
}

void Oscilloscope::reset() {
    m_writeIndex = 0;
    m_pointCount = 0;
}
