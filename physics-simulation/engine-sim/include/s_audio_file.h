#ifndef S_AUDIO_FILE_H
#define S_AUDIO_FILE_H

#include <AudioToolbox/AudioToolbox.h>

typedef unsigned int SampleOffset; 

class sAudioFile {
public: 
    sAudioFile(); 
    ~sAudioFile(); 

    enum class AudioFormat { Wave, Undefined }; 
    enum class Error {
        None, CouldNotOpenFile, InvalidFileFormat, FileAlreadyOpen, 
        NoFileOpen, ReadOutOfRange, FileReadError, CouldNotLockBuffer, 
        InvalidParam, OutOfMemory
    }; 

    Error OpenFile(const char* fname); 
    Error CloseFile(); 
    Error InitializeInternalBuffer(SampleOffset samples, bool saveData = false); 
    Error FillBuffer(SampleOffset offset); 

    const void* GetBuffer() const { return m_buffer; }
    void DestroyInternalBuffer(); 
    SampleOffset GetSampleCount() const { return m_sampleCount; }

protected: 
    Error GenericRead(SampleOffset offset, SampleOffset size, void* buffer);

    ExtAudioFileRef m_fileRef;
    bool m_fileOpen;
    char* m_buffer; 
    SampleOffset m_sampleCount; 
    SampleOffset m_maxBufferSamples;
    
    struct {
        int m_channelCount;
        int m_sampleRate;
        int m_bitsPerSample;
        int GetSizeFromSamples(SampleOffset s) { return s * m_channelCount * (m_bitsPerSample / 8); }
    } m_audioParams;
}; 

#endif