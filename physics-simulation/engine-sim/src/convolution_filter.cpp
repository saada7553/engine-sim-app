#include "../include/convolution_filter.h"
#include <assert.h>
#include <string.h>
#include <Accelerate/Accelerate.h>

ConvolutionFilter::ConvolutionFilter() {
    m_shiftRegister = nullptr;
    m_impulseResponse = nullptr;

    m_shiftOffset = 0;
    m_sampleCount = 0;
}

ConvolutionFilter::~ConvolutionFilter() {
    assert(m_shiftRegister == nullptr);
    assert(m_impulseResponse == nullptr);
}

void ConvolutionFilter::initialize(int samples) {
    m_sampleCount = samples;
    m_shiftOffset = 0;
    m_shiftRegister = new float[samples];
    m_impulseResponse = new float[samples];

    memset(m_shiftRegister, 0, sizeof(float) * samples);
    memset(m_impulseResponse, 0, sizeof(float) * samples);
}

void ConvolutionFilter::destroy() {
    delete[] m_shiftRegister;
    delete[] m_impulseResponse;

    m_shiftRegister = nullptr;
    m_impulseResponse = nullptr;
}

float ConvolutionFilter::f(float sample) {
    m_shiftRegister[m_shiftOffset] = sample;

    float result = 0;
    const int firstPartLen = m_sampleCount - m_shiftOffset;
    const int secondPartLen = m_shiftOffset;

    float r1 = 0, r2 = 0;
    if (firstPartLen > 0) {
        vDSP_dotpr(m_impulseResponse, 1,
                   m_shiftRegister + m_shiftOffset, 1,
                   &r1, firstPartLen);
    }
    if (secondPartLen > 0) {
        vDSP_dotpr(m_impulseResponse + firstPartLen, 1,
                   m_shiftRegister, 1,
                   &r2, secondPartLen);
    }
    
    result = r1 + r2;
    m_shiftOffset = (m_shiftOffset - 1 + m_sampleCount) % m_sampleCount;

    return result;
}
