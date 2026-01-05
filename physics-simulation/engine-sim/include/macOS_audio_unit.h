#ifndef MACOS_AUDIO_ADAPTER_H
#define MACOS_AUDIO_ADAPTER_H

#include <AudioUnit/AudioUnit.h>
#include "synthesizer.h"

class MacOSAudioAdapter {
public:
    MacOSAudioAdapter();
    ~MacOSAudioAdapter();

    // Initializes the AudioUnit and sets up the format
    bool Initialize(Synthesizer* synth);
    
    // Starts the hardware audio clock
    void Start();
    
    // Stops the hardware audio clock
    void Stop();

    // Cleans up the AudioUnit
    void Destroy();

private:
    // The bridge between macOS hardware and the Synthesizer
    static OSStatus RenderCallback(
        void *inRefCon, 
        AudioUnitRenderActionFlags *ioActionFlags, 
        const AudioTimeStamp *inTimeStamp, 
        UInt32 inBusNumber, 
        UInt32 inNumberFrames, 
        AudioBufferList *ioData
    );

    float m_last_read; 
    Synthesizer* m_synth;
    AudioUnit m_outputUnit;
    bool m_initialized;
};

#endif