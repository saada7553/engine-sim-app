#include "../include/s_audio_file.h"
#include <new> 
#include <CoreFoundation/CoreFoundation.h>

sAudioFile::sAudioFile() {
    m_fileRef = nullptr;
    m_fileOpen = false;
    m_buffer = nullptr;
    m_sampleCount = 0;
    m_maxBufferSamples = 0;
}

sAudioFile::~sAudioFile() {
    CloseFile();
    DestroyInternalBuffer();
}

sAudioFile::Error sAudioFile::OpenFile(const char* fname) {
    if (m_fileOpen) return Error::FileAlreadyOpen;

    // Convert C-string path to CFURL
    CFStringRef path = CFStringCreateWithCString(kCFAllocatorDefault, fname, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, false);
    CFRelease(path);

    // Open the audio file
    OSStatus status = ExtAudioFileOpenURL(url, &m_fileRef);
    CFRelease(url);

    if (status != noErr) return Error::CouldNotOpenFile;

    // Get the file data format
    AudioStreamBasicDescription fileFormat;
    UInt32 propSize = sizeof(fileFormat);
    ExtAudioFileGetProperty(m_fileRef, kExtAudioFileProperty_FileDataFormat, &propSize, &fileFormat);

    m_audioParams.m_channelCount = fileFormat.mChannelsPerFrame;
    m_audioParams.m_sampleRate = fileFormat.mSampleRate;
    m_audioParams.m_bitsPerSample = fileFormat.mBitsPerChannel;

    // Get total length in frames (samples)
    SInt64 totalFrames = 0;
    propSize = sizeof(totalFrames);
    ExtAudioFileGetProperty(m_fileRef, kExtAudioFileProperty_FileLengthFrames, &propSize, &totalFrames);
    m_sampleCount = (SampleOffset)totalFrames;

    // Set the client format to Linear PCM (Ensures we get raw data regardless of source format)
    AudioStreamBasicDescription clientFormat = fileFormat;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;

    ExtAudioFileSetProperty(m_fileRef, kExtAudioFileProperty_ClientDataFormat, sizeof(clientFormat), &clientFormat);

    m_fileOpen = true;
    return Error::None; 
}

sAudioFile::Error sAudioFile::GenericRead(SampleOffset offset, SampleOffset size, void* target) {
    if (!m_fileOpen) return Error::NoFileOpen;

    // Seek to the requested offset
    OSStatus status = ExtAudioFileSeek(m_fileRef, (SInt64)offset);
    if (status != noErr) return Error::ReadOutOfRange;

    // Set up the buffer list for reading
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = m_audioParams.m_channelCount;
    bufferList.mBuffers[0].mDataByteSize = m_audioParams.GetSizeFromSamples(size);
    bufferList.mBuffers[0].mData = target;

    UInt32 framesToRead = size;
    status = ExtAudioFileRead(m_fileRef, &framesToRead, &bufferList);

    if (status != noErr) return Error::FileReadError;
    return Error::None;
}

sAudioFile::Error sAudioFile::FillBuffer(SampleOffset offset) {
    if (!m_buffer) return Error::NoFileOpen;
    if (offset + m_maxBufferSamples > m_sampleCount) return Error::ReadOutOfRange;

    return GenericRead(offset, m_maxBufferSamples, (void*)m_buffer);
}

sAudioFile::Error sAudioFile::InitializeInternalBuffer(SampleOffset samples, bool saveData) {
    if (!m_fileOpen) return Error::NoFileOpen;

    int newSize = m_audioParams.GetSizeFromSamples(samples);
    char* newBuffer = new (std::nothrow) char[newSize];
    if (!newBuffer) return Error::OutOfMemory;

    if (saveData && m_buffer) {
        int copySize = m_audioParams.GetSizeFromSamples(m_maxBufferSamples < samples ? m_maxBufferSamples : samples);
        memcpy(newBuffer, m_buffer, copySize);
    }

    DestroyInternalBuffer();
    m_buffer = newBuffer;
    m_maxBufferSamples = samples;

    return Error::None;
}

void sAudioFile::DestroyInternalBuffer() {
    if (m_buffer) {
        delete[] m_buffer;
        m_buffer = nullptr;
    }
    m_maxBufferSamples = 0;
}

sAudioFile::Error sAudioFile::CloseFile() {
    if (!m_fileOpen) return Error::NoFileOpen;

    if (m_fileRef) {
        ExtAudioFileDispose(m_fileRef);
        m_fileRef = nullptr;
    }
    
    m_fileOpen = false;
    return Error::None; 
}