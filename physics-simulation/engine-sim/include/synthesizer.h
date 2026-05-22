#ifndef ATG_ENGINE_SIM_ENGINE_SYNTHESIZER_H
#define ATG_ENGINE_SIM_ENGINE_SYNTHESIZER_H

#include "convolution_filter.h"
#include "leveling_filter.h"
#include "derivative_filter.h"
#include "low_pass_filter.h"
#include "jitter_filter.h"
#include "ring_buffer.h"
#include "butterworth_low_pass_filter.h"

#include <cinttypes>
#include <thread>
#include <mutex>
#include <atomic>
#include <condition_variable>

class Synthesizer {
    public:
        struct AudioParameters {
            float volume = 1.0f;
            float convolution = 1.0f;
            float dF_F_mix = 0.01f;
            float inputSampleNoise = 0.5f;
            float inputSampleNoiseFrequencyCutoff = 10000.0f;
            float airNoise = 1.0f;
            float airNoiseFrequencyCutoff = 2000.0f;
            float levelerTarget = 30000.0f;
            float levelerMaxGain = 1.9f;
            float levelerMinGain = 0.00001f;
        };

        struct Parameters {
            int inputChannelCount = 1;
            int inputBufferSize = 1024;
            int audioBufferSize = 44100;
            float inputSampleRate = 10000;
            float audioSampleRate = 44100;
            AudioParameters initialAudioParameters;
        };

        struct InputChannel {
            RingBuffer<float> data;
            float *transferBuffer = nullptr;
            double lastInputSample = 0.0f;
        };

        struct ProcessingFilters {
            ConvolutionFilter convolution;
            DerivativeFilter derivative;
            JitterFilter jitterFilter;
            ButterworthLowPassFilter<float> airNoiseLowPass;
            LowPassFilter inputDcFilter;
            ButterworthLowPassFilter<double> antialiasing;
        };

    public:
        Synthesizer();
        ~Synthesizer();

        void initialize(const Parameters &p);
        void initializeImpulseResponse(
            const int16_t *impulseResponse,
            unsigned int samples,
            float volume,
            int index);
        void startAudioRenderingThread();
        void endAudioRenderingThread();
        void destroy();

        int readAudioOutput(int samples, int16_t *buffer);

        // `dry` is an extra signal (the catastrophe boom/clanks) that BYPASSES
        // the per-channel exhaust processing — the derivative emphasis, the
        // air-noise multiply and especially the impulse-response CONVOLUTION
        // (a ~200ms reverberant exhaust IR that would smear it into echo and
        // filter out its low end). It is normalized to ~[-1,1] and added to the
        // post-convolution signal, scaled to the exhaust loudness in renderAudio.
        void writeInput(const double *data, double dry = 0.0);
        void endInputBlock();

        void waitProcessed();

        void audioRenderingThread();
        void renderAudio();

        double getLatency() const;

        int inputDelta(int s1, int s0) const;
        double inputDistance(double s1, double s0) const;

        void setInputSampleRate(double sampleRate);
        double getInputSampleRate() const { return m_inputSampleRate; }

        int16_t renderAudio(int inputOffset);

        double getLevelerGain();
        AudioParameters getAudioParameters();
        void setAudioParameters(const AudioParameters &params);

        // Live peak-follower envelope (~[0,1]) of the DRY catastrophe signal
        // (boom + clanks). Written per-sample on the audio thread, read by the
        // UI poll thread to drive haptics that follow the crash sound in real
        // time. atomic<float> read so the cross-thread read is well-defined.
        float getCatastropheEnvelope() const {
            return m_catHapticEnv.load(std::memory_order_relaxed);
        }

        // Peak |dry catastrophe| since the last call, then RESET to 0. Unlike
        // the smoothed envelope, this captures the loudest crash impact in each
        // UI poll window regardless of poll rate, so the haptics can punch on
        // every boom/clank and feel different as the random sound varies.
        float getCatastrophePeak() {
            return m_catHapticPeak.exchange(0.0f, std::memory_order_relaxed);
        }

    //protected:
        ButterworthLowPassFilter<float> m_antialiasing;
        LevelingFilter m_levelingFilter;
        InputChannel *m_inputChannels;
        AudioParameters m_audioParameters;
        int m_inputChannelCount;
        int m_inputBufferSize;
        int m_inputSamplesRead;
        int m_latency;
        double m_inputWriteOffset;
        double m_lastInputSampleOffset;

        RingBuffer<int16_t> m_audioBuffer;
        int m_audioBufferSize;

        // Dry catastrophe path (bypasses convolution; see writeInput).
        RingBuffer<float> m_dryChannel;
        float *m_dryTransferBuffer = nullptr;
        double m_dryLastSample = 0.0;
        ButterworthLowPassFilter<double> m_dryAntialiasing;

        // Peak-follower envelope of the dry catastrophe signal (see
        // getCatastropheEnvelope). Snaps up to new peaks, bleeds down slowly.
        std::atomic<float> m_catHapticEnv{0.0f};
        // Peak-hold of the dry catastrophe signal since the last UI read (see
        // getCatastrophePeak). Reset to 0 on read.
        std::atomic<float> m_catHapticPeak{0.0f};

        float m_inputSampleRate;
        float m_audioSampleRate;

        std::thread *m_thread;
        std::atomic<bool> m_run;
        bool m_processed;

        std::mutex m_inputLock;
        std::mutex m_lock0;
        std::condition_variable m_cv0;

        ProcessingFilters *m_filters;
};

#endif /* ATG_ENGINE_SIM_ENGINE_SYNTHESIZER_H */
