//
//  AKSamplerDSP.cpp
//  ExtendingAudioKit
//
//  Created by Shane Dunne on 2018-02-19.
//  Copyright © 2018 Shane Dunne & Associates. All rights reserved.
//

#import "AKSamplerDSP.hpp"

extern "C" void* createAKSamplerDSP(int nChannels, double sampleRate) {
    return new AKSamplerDSP();
}

extern "C" void doAKSamplerLoadData(void* pDSP, AKSampleDataDescriptor* pSDD) {
    ((AKSamplerDSP*)pDSP)->loadSampleData(*pSDD);
}

extern "C" void doAKSamplerLoadCompressedFile(void* pDSP, AKSampleFileDescriptor* pSFD)
{
    ((AKSamplerDSP*)pDSP)->loadCompressedSampleFile(*pSFD);
}

extern "C" void doAKSamplerUnloadAllSamples(void* pDSP)
{
    ((AKSamplerDSP*)pDSP)->deinit();
}

extern "C" void doAKSamplerBuildSimpleKeyMap(void* pDSP) {
    ((AKSamplerDSP*)pDSP)->buildSimpleKeyMap();
}

extern "C" void doAKSamplerBuildKeyMap(void* pDSP) {
    ((AKSamplerDSP*)pDSP)->buildKeyMap();
}

extern "C" void doAKSamplerPlayNote(void* pDSP, UInt8 noteNumber, UInt8 velocity, float noteHz)
{
    ((AKSamplerDSP*)pDSP)->playNote(noteNumber, velocity, noteHz);
}

extern "C" void doAKSamplerStopNote(void* pDSP, UInt8 noteNumber, bool immediate)
{
    ((AKSamplerDSP*)pDSP)->stopNote(noteNumber, immediate);
}

extern "C" void doAKSamplerSustainPedal(void* pDSP, bool pedalDown)
{
    ((AKSamplerDSP*)pDSP)->sustainPedal(pedalDown);
}


AKSamplerDSP::AKSamplerDSP() : AudioKitCore::Sampler()
{
    masterVolumeRamp.setTarget(1.0, true);
    pitchBendRamp.setTarget(0.0, true);
    vibratoDepthRamp.setTarget(0.0, true);
    filterCutoffRamp.setTarget(1000.0, true);
    filterResonanceRamp.setTarget(0.0, true);
}

void AKSamplerDSP::init(int nChannels, double sampleRate)
{
    AKDSPBase::init(nChannels, sampleRate);
    AudioKitCore::Sampler::init(sampleRate);
}

void AKSamplerDSP::deinit()
{
    AudioKitCore::Sampler::deinit();
}

void AKSamplerDSP::setParameter(uint64_t address, float value, bool immediate)
{
    switch (address) {
        case rampTimeParam:
            masterVolumeRamp.setRampTime(value, _sampleRate);
            pitchBendRamp.setRampTime(value, _sampleRate);
            vibratoDepthRamp.setRampTime(value, _sampleRate);
            filterCutoffRamp.setRampTime(value, _sampleRate);
            filterResonanceRamp.setRampTime(value, _sampleRate);
            break;

        case masterVolumeParam:
            masterVolumeRamp.setTarget(value, immediate);
            break;
        case pitchBendParam:
            pitchBendRamp.setTarget(value, immediate);
            break;
        case vibratoDepthParam:
            vibratoDepthRamp.setTarget(value, immediate);
            break;
        case filterCutoffParam:
            filterCutoffRamp.setTarget(value, immediate);
            break;
        case filterResonanceParam:
            filterResonanceRamp.setTarget(value, immediate);
            break;

        case ampAttackTimeParam:
            ampEGParams.setAttackTimeSeconds(value);
            break;
        case ampDecayTimeParam:
            ampEGParams.setDecayTimeSeconds(value);
            break;
        case ampSustainLevelParam:
            ampEGParams.sustainFraction = value;
            break;
        case ampReleaseTimeParam:
            ampEGParams.setReleaseTimeSeconds(value);
            break;

        case filterAttackTimeParam:
            filterEGParams.setAttackTimeSeconds(value);
            break;
        case filterDecayTimeParam:
            filterEGParams.setDecayTimeSeconds(value);
            break;
        case filterSustainLevelParam:
            filterEGParams.sustainFraction = value;
            break;
        case filterReleaseTimeParam:
            filterEGParams.setReleaseTimeSeconds(value);
            break;
        case filterEnableParam:
            filterEnable = value > 0.5f;
            break;
    }
}

float AKSamplerDSP::getParameter(uint64_t address)
{
    switch (address) {
        case rampTimeParam:
            return pitchBendRamp.getRampTime(_sampleRate);

        case masterVolumeParam:
            return masterVolumeRamp.getTarget();
        case pitchBendParam:
            return pitchBendRamp.getTarget();
        case vibratoDepthParam:
            return vibratoDepthRamp.getTarget();
        case filterCutoffParam:
            return filterCutoffRamp.getTarget();
        case filterResonanceParam:
            return filterResonanceRamp.getTarget();

        case ampAttackTimeParam:
            return ampEGParams.getAttackTimeSeconds();
        case ampDecayTimeParam:
            return ampEGParams.getDecayTimeSeconds();
        case ampSustainLevelParam:
            return ampEGParams.sustainFraction;
        case ampReleaseTimeParam:
            return ampEGParams.getReleaseTimeSeconds();

        case filterAttackTimeParam:
            return filterEGParams.getAttackTimeSeconds();
        case filterDecayTimeParam:
            return filterEGParams.getDecayTimeSeconds();
        case filterSustainLevelParam:
            return filterEGParams.sustainFraction;
        case filterReleaseTimeParam:
            return filterEGParams.getReleaseTimeSeconds();
        case filterEnableParam:
            return filterEnable ? 1.0f : 0.0f;
    }
    return 0;
}

void AKSamplerDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset)
{
    // process in chunks of maximum length CHUNKSIZE
    for (int frameIndex = 0; frameIndex < frameCount; frameIndex += CHUNKSIZE) {
        int frameOffset = int(frameIndex + bufferOffset);
        int chunkSize = frameCount - frameIndex;
        if (chunkSize > CHUNKSIZE) chunkSize = CHUNKSIZE;
        
        // ramp parameters
        masterVolumeRamp.advanceTo(_now + frameOffset);
        masterVolume = (float)masterVolumeRamp.getValue();
        pitchBendRamp.advanceTo(_now + frameOffset);
        pitchOffset = (float)pitchBendRamp.getValue();
        vibratoDepthRamp.advanceTo(_now + frameOffset);
        vibratoDepth = (float)vibratoDepthRamp.getValue();
        filterCutoffRamp.advanceTo(_now + frameOffset);
        cutoffMultiple = (float)filterCutoffRamp.getValue();
        resonanceDb = (float)filterResonanceRamp.getValue();
        
        // get data
        float *outBuffers[2];
        outBuffers[0] = (float*)_outBufferListPtr->mBuffers[0].mData + frameOffset;
        outBuffers[1] = (float*)_outBufferListPtr->mBuffers[1].mData + frameOffset;
        unsigned channelCount = _outBufferListPtr->mNumberBuffers;
        AudioKitCore::Sampler::Render(channelCount, chunkSize, outBuffers);
    }
}