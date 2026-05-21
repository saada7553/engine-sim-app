#include "../include/macOS_audio_unit.h"
#include <AudioToolbox/AudioToolbox.h>
#include <TargetConditionals.h>
#include <algorithm>
#include <vector>
#include <iostream>

// macOS uses the DefaultOutput AudioUnit subtype to route playback to the
// currently-selected system output. iOS doesn't have that subtype — its
// equivalent is RemoteIO. The rest of the AudioUnit property dance is
// identical, so we only branch on the subtype. AVAudioSession activation on
// iOS is handled from the Swift app target.
#if TARGET_OS_IOS
static constexpr OSType kEngineSimOutputUnitSubType = kAudioUnitSubType_RemoteIO;
#else
static constexpr OSType kEngineSimOutputUnitSubType = kAudioUnitSubType_DefaultOutput;
#endif

MacOSAudioAdapter::MacOSAudioAdapter() {
    m_synth = nullptr;
    m_outputUnit = nullptr;
    m_initialized = false;
    m_last_read = 0.0; 
}

MacOSAudioAdapter::~MacOSAudioAdapter() {
    Destroy();
}

bool MacOSAudioAdapter::Initialize(Synthesizer* synth) {
    if (m_initialized) return true;
    m_synth = synth;

    // 1. Describe the Default Output (macOS) or RemoteIO (iOS).
    AudioComponentDescription desc = {};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kEngineSimOutputUnitSubType;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) return false;

    if (AudioComponentInstanceNew(comp, &m_outputUnit) != noErr) return false;

    // 2. Set the Render Callback
    AURenderCallbackStruct cb;
    cb.inputProc = MacOSAudioAdapter::RenderCallback;
    cb.inputProcRefCon = this;
    
    OSStatus status = AudioUnitSetProperty(
        m_outputUnit, 
        kAudioUnitProperty_SetRenderCallback, 
        kAudioUnitScope_Input, 
        0, 
        &cb, 
        sizeof(cb)
    );
    if (status != noErr) return false;

    // 3. Define the Stream Format (Mono 32-bit Float)
    // CoreAudio works best with Float32. We output Mono to match the engine.
    AudioStreamBasicDescription format = {};
    format.mSampleRate       = 40000.0; // SUS, wrong sampling (44100)
    format.mFormatID         = kAudioFormatLinearPCM;
    format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mFramesPerPacket  = 1;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel   = 32;
    format.mBytesPerFrame    = 4;
    format.mBytesPerPacket   = 4;

    status = AudioUnitSetProperty(
        m_outputUnit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        0,
        &format,
        sizeof(format)
    );
    if (status != noErr) return false;

    if (AudioUnitInitialize(m_outputUnit) != noErr) return false;

    m_initialized = true;
    return true;
}

OSStatus MacOSAudioAdapter::RenderCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    // High-performance audio thread - avoid allocations here!
    MacOSAudioAdapter* adapter = static_cast<MacOSAudioAdapter*>(inRefCon);
    if (!adapter->m_synth) return noErr;

    float* outBuffer = static_cast<float*>(ioData->mBuffers[0].mData);

    // Using a member vector would require locking, which is bad in audio callbacks.
    // Allocating on stack is safe for small sizes (Audio Units usually ask for < 1024 frames).
    // We safeguard against huge requests.
    const int MAX_STACK_SAMPLES = 1024;
    int16_t localBuffer[MAX_STACK_SAMPLES];

    UInt32 framesToRead = (inNumberFrames > MAX_STACK_SAMPLES) ? MAX_STACK_SAMPLES : inNumberFrames;

    // Pull data from the Engine Synthesizer
    // This removes data from the RingBuffer, signaling the synth thread to wake up.
    int samplesRead = adapter->m_synth->readAudioOutput(framesToRead, localBuffer);

//    if (samplesRead < framesToRead)
//        std::cout << samplesRead << '/' << framesToRead << std::endl; 

    // for (int i = 0; i < samplesRead; ++i) {
    //     std::cout << localBuffer[i] << std::endl;
    // }

    // Convert Int16 -> Float32
    for (int i = 0; i < samplesRead; ++i) {
        outBuffer[i] = localBuffer[i] / 32768.0f;
    }

    if (samplesRead > 0)
        adapter->m_last_read = outBuffer[samplesRead - 1];

    // Handle Buffer Underrun (The engine wasn't fast enough)
    if (samplesRead < inNumberFrames) {
        // Option A: Silence (standard)
        // std::fill(outBuffer + samplesRead, outBuffer + inNumberFrames, 0.0f);

        // Option B: Hold last sample (reduces "clicking" sound slightly)
        // float lastSample = (samplesRead > 0) ? outBuffer[samplesRead - 1] : 0.0f;
        // std::cout <<  adapter->m_last_read << " last " << std::endl; 

        std::fill(outBuffer + samplesRead, outBuffer + inNumberFrames, adapter->m_last_read);
    }

    // for(int i = 0; i < inNumberFrames; ++i) {
    //     std::cout << outBuffer[i] << std::endl;
    // }

    return noErr;
}

void MacOSAudioAdapter::Start() {
    if (m_initialized) AudioOutputUnitStart(m_outputUnit);
}

void MacOSAudioAdapter::Stop() {
    if (m_initialized) AudioOutputUnitStop(m_outputUnit);
}

void MacOSAudioAdapter::Destroy() {
    if (m_initialized) {
        Stop();
        AudioUnitUninitialize(m_outputUnit);
        AudioComponentInstanceDispose(m_outputUnit);
        m_initialized = false;
    }
}
