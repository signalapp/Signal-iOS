#import "AppAudioManager.h"
#import "Constraints.h"
#import "Environment.h"
#import "RemoteIOAudio.h"
#import "ThreadManager.h"
#import "Util.h"

#define INPUT_BUS 1
#define OUTPUT_BUS 0
#define INITIAL_NUMBER_OF_BUFFERS 100
#define SAMPLE_SIZE_IN_BYTES 2

#define BUFFER_SIZE 8000

#define FLAG_MUTED 1
#define FLAG_UNMUTED 0

@implementation RemoteIOAudio

@synthesize playbackQueue, recordingQueue, rioAudioUnit, state;

static bool doesActiveInstanceExist;

+ (RemoteIOAudio *)remoteIOInterfaceStartedWithDelegate:(id<AudioCallbackHandler>)delegateIn
                                         untilCancelled:(TOCCancelToken *)untilCancelledToken {
    checkOperationDescribe(
        !doesActiveInstanceExist,
        @"Only one RemoteIOInterfance instance can exist at a time. Adding more will break previous instances.");
    doesActiveInstanceExist = true;

    RemoteIOAudio *newRemoteIoInterface = [RemoteIOAudio new];
    newRemoteIoInterface->starveLogger =
        [Environment.logging getOccurrenceLoggerForSender:newRemoteIoInterface withKey:@"starve"];
    newRemoteIoInterface->conditionLogger = [Environment.logging getConditionLoggerForSender:newRemoteIoInterface];
    newRemoteIoInterface->recordingQueue  = [CyclicalBuffer new];
    newRemoteIoInterface->playbackQueue   = [CyclicalBuffer new];
    newRemoteIoInterface->unusedBuffers   = [NSMutableSet set];
    newRemoteIoInterface->state           = NOT_STARTED;
    newRemoteIoInterface->playbackBufferSizeLogger =
        [Environment.logging getValueLoggerForValue:@"|playback queue|" from:newRemoteIoInterface];
    newRemoteIoInterface->recordingQueueSizeLogger =
        [Environment.logging getValueLoggerForValue:@"|recording queue|" from:newRemoteIoInterface];

    while (newRemoteIoInterface->unusedBuffers.count < INITIAL_NUMBER_OF_BUFFERS) {
        [newRemoteIoInterface addUnusedBuffer];
    }
    [newRemoteIoInterface setupAudio];

    [newRemoteIoInterface startWithDelegate:delegateIn untilCancelled:untilCancelledToken];

    return newRemoteIoInterface;
}

- (void)setupAudio {
    [AppAudioManager.sharedInstance requestRecordingPrivilege];
    rioAudioUnit = [self makeAudioUnit];
    [self setAudioEnabled];
    [self setAudioStreamFormat];
    [self setAudioCallbacks];
    [self unsetAudioShouldAllocateBuffer];
    [self checkDone:AudioUnitInitialize(rioAudioUnit)];
    [[AppAudioManager sharedInstance] updateAudioRouter];
}
- (AudioUnit)makeAudioUnit {
    AudioComponentDescription audioUnitDescription = [self makeAudioComponentDescription];
    AudioComponent component                       = AudioComponentFindNext(NULL, &audioUnitDescription);

    AudioUnit unit;
    [self checkDone:AudioComponentInstanceNew(component, &unit)];
    return unit;
}
- (AudioComponentDescription)makeAudioComponentDescription {
    AudioComponentDescription d;
    d.componentType         = kAudioUnitType_Output;
    d.componentSubType      = kAudioUnitSubType_VoiceProcessingIO;
    d.componentManufacturer = kAudioUnitManufacturer_Apple;
    d.componentFlags        = 0;
    d.componentFlagsMask    = 0;
    return d;
}
- (void)setAudioEnabled {
    const UInt32 enable = 1;
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Input,
                                         INPUT_BUS,
                                         &enable,
                                         sizeof(enable))];
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Output,
                                         OUTPUT_BUS,
                                         &enable,
                                         sizeof(enable))];
}
- (void)setAudioStreamFormat {
    const AudioStreamBasicDescription streamDesc = [self makeAudioStreamBasicDescription];
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         OUTPUT_BUS,
                                         &streamDesc,
                                         sizeof(streamDesc))];
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Output,
                                         INPUT_BUS,
                                         &streamDesc,
                                         sizeof(streamDesc))];
}
- (AudioStreamBasicDescription)makeAudioStreamBasicDescription {
    const UInt32 framesPerPacket = 1;
    AudioStreamBasicDescription d;
    d.mSampleRate       = SAMPLE_RATE;
    d.mFormatID         = kAudioFormatLinearPCM;
    d.mFramesPerPacket  = framesPerPacket;
    d.mChannelsPerFrame = 1;
    d.mBitsPerChannel   = 16;
    d.mBytesPerPacket   = SAMPLE_SIZE_IN_BYTES;
    d.mBytesPerFrame    = framesPerPacket * SAMPLE_SIZE_IN_BYTES;
    d.mReserved         = 0;
    d.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    return d;
}
- (void)setAudioCallbacks {
    const AURenderCallbackStruct recordingCallbackStruct = {recordingCallback, (__bridge void *)(self)};
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioOutputUnitProperty_SetInputCallback,
                                         kAudioUnitScope_Global,
                                         INPUT_BUS,
                                         &recordingCallbackStruct,
                                         sizeof(recordingCallbackStruct))];

    const AURenderCallbackStruct playbackCallbackStruct = {playbackCallback, (__bridge void *)(self)};
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioUnitProperty_SetRenderCallback,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &playbackCallbackStruct,
                                         sizeof(playbackCallbackStruct))];
}
- (void)unsetAudioShouldAllocateBuffer {
    const UInt32 shouldAllocateBuffer = 0;
    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAudioUnitProperty_ShouldAllocateBuffer,
                                         kAudioUnitScope_Output,
                                         INPUT_BUS,
                                         &shouldAllocateBuffer,
                                         sizeof(shouldAllocateBuffer))];
}

- (RemoteIOBufferListWrapper *)addUnusedBuffer {
    RemoteIOBufferListWrapper *buf = [RemoteIOBufferListWrapper remoteIOBufferListWithMonoBufferSize:BUFFER_SIZE];
    [unusedBuffers addObject:buf];
    return buf;
}
- (RemoteIOBufferListWrapper *)tryTakeUnusedBuffer {
    RemoteIOBufferListWrapper *buffer = (RemoteIOBufferListWrapper *)[unusedBuffers anyObject];
    if (buffer == nil)
        return nil;
    [unusedBuffers removeObject:buffer];
    return buffer;
}
- (void)returnUsedBuffer:(RemoteIOBufferListWrapper *)buffer {
    ows_require(buffer != nil);
    if (state == TERMINATED)
        return; // in case a buffer was in use as termination occurred
    [unusedBuffers addObject:buffer];
}

- (void)startWithDelegate:(id<AudioCallbackHandler>)delegateIn untilCancelled:(TOCCancelToken *)untilCancelledToken {
    ows_require(delegateIn != nil);
    @synchronized(self) {
        requireState(state == NOT_STARTED);

        delegate = delegateIn;
        [self checkDone:AudioOutputUnitStart(rioAudioUnit)];
        state = STARTED;
    }

    [untilCancelledToken whenCancelledDo:^{
      @synchronized(self) {
          state                   = TERMINATED;
          doesActiveInstanceExist = false;
          [self checkDone:AudioOutputUnitStop(rioAudioUnit)];
          [AppAudioManager.sharedInstance releaseRecordingPrivilege];
          [unusedBuffers removeAllObjects];
      }
    }];
}

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberSamples,
                                  AudioBufferList *ioData) {
    @autoreleasepool {
        RemoteIOAudio *instance = (__bridge RemoteIOAudio *)inRefCon;

        RemoteIOBufferListWrapper *buffer;
        @synchronized(instance) {
            buffer = [instance tryTakeUnusedBuffer];
        }
        if (buffer == nil) {
            // All buffers in use. Drop recorded audio.
            return 1; // arbitrary error code
        }
        AudioBufferList bufferList = *[buffer audioBufferList];
        [instance checkDone:AudioUnitRender([instance rioAudioUnit],
                                            ioActionFlags,
                                            inTimeStamp,
                                            inBusNumber,
                                            inNumberSamples,
                                            &bufferList)];
        buffer.sampleCount = inNumberSamples;

        [instance performSelector:@selector(onRecordedDataIntoBuffer:)
                         onThread:[ThreadManager lowLatencyThread]
                       withObject:buffer
                    waitUntilDone:NO];
    }
    return noErr;
}
- (void)onRecordedDataIntoBuffer:(RemoteIOBufferListWrapper *)buffer {
    @synchronized(self) {
        if (state == TERMINATED)
            return;
        NSData *recordedAudioVolatile = [NSData dataWithBytesNoCopy:[buffer audioBufferList]->mBuffers[0].mData
                                                             length:[buffer sampleCount] * SAMPLE_SIZE_IN_BYTES
                                                       freeWhenDone:NO];
        [recordingQueue enqueueData:recordedAudioVolatile];
        [self returnUsedBuffer:buffer];
    }

    [recordingQueueSizeLogger logValue:[recordingQueue enqueuedLength]];
    [delegate handleNewDataRecorded:recordingQueue];
}

- (void)populatePlaybackQueueWithData:(NSData *)data {
    ows_require(data != nil);
    if (data.length == 0)
        return;
    @synchronized(self) {
        [playbackQueue enqueueData:data];
    }
}
static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberSamples,
                                 AudioBufferList *ioData) {
    RemoteIOAudio *instance       = (__bridge RemoteIOAudio *)inRefCon;
    NSUInteger requestedByteCount = inNumberSamples * SAMPLE_SIZE_IN_BYTES;
    NSUInteger availableByteCount;
    @synchronized(instance) {
        availableByteCount = [[instance playbackQueue] enqueuedLength];

        if (availableByteCount < requestedByteCount) {
            NSUInteger starveAmount = requestedByteCount - availableByteCount;
            [instance->starveLogger markOccurrence:@(starveAmount)];
        } else {
            NSData *audioToCopyVolatile =
                [[instance playbackQueue] dequeuePotentialyVolatileDataWithLength:requestedByteCount];
            memcpy(ioData->mBuffers[0].mData, [audioToCopyVolatile bytes], audioToCopyVolatile.length);
        }
    }

    [Operation asyncRun:^{
      [instance onRequestedPlaybackDataAmount:requestedByteCount andHadAvailableAmount:availableByteCount];
    }
               onThread:[ThreadManager lowLatencyThread]];

    if (availableByteCount < requestedByteCount) {
        return 1; // arbitrary error code
    }

    return noErr;
}
- (void)onRequestedPlaybackDataAmount:(NSUInteger)requestedByteCount
                andHadAvailableAmount:(NSUInteger)availableByteCount {
    @synchronized(self) {
        if (state == TERMINATED)
            return;
    }
    NSUInteger consumedByteCount  = availableByteCount >= requestedByteCount ? requestedByteCount : 0;
    NSUInteger remainingByteCount = availableByteCount - consumedByteCount;
    [playbackBufferSizeLogger logValue:remainingByteCount];
    [delegate handlePlaybackOccurredWithBytesRequested:requestedByteCount andBytesRemaining:remainingByteCount];
}

- (void)dealloc {
    if (state != TERMINATED) {
        doesActiveInstanceExist = false;
    }
}

- (NSUInteger)getSampleRateInHertz {
    return SAMPLE_RATE;
}

- (void)checkDone:(OSStatus)resultCode {
    if (resultCode == kAudioSessionNoError)
        return;

    NSString *failure;
    if (resultCode == kAudioServicesUnsupportedPropertyError) {
        failure = @"unsupportedPropertyError";
    } else if (resultCode == kAudioServicesBadPropertySizeError) {
        failure = @"badPropertySizeError";
    } else if (resultCode == kAudioServicesBadSpecifierSizeError) {
        failure = @"badSpecifierSizeError";
    } else if (resultCode == kAudioServicesSystemSoundUnspecifiedError) {
        failure = @"systemSoundUnspecifiedError";
    } else if (resultCode == kAudioServicesSystemSoundClientTimedOutError) {
        failure = @"systemSoundClientTimedOutError";
    } else if (resultCode == errSecParam) {
        failure = @"oneOrMoreNonValidParameter";
    } else {
        failure = [@(resultCode) description];
    }
    [conditionLogger logError:[NSString stringWithFormat:@"StatusCheck failed: %@", failure]];
}

- (bool)isAudioMuted {
    UInt32 currentMuteFlag;
    UInt32 propertyByteSize;
    [self checkDone:AudioUnitGetProperty(rioAudioUnit,
                                         kAUVoiceIOProperty_MuteOutput,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &currentMuteFlag,
                                         &propertyByteSize)];
    return (FLAG_MUTED == currentMuteFlag);
}

- (BOOL)toggleMute {
    BOOL shouldBeMuted = !self.isAudioMuted;
    UInt32 newValue    = shouldBeMuted ? FLAG_MUTED : FLAG_UNMUTED;

    [self checkDone:AudioUnitSetProperty(rioAudioUnit,
                                         kAUVoiceIOProperty_MuteOutput,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &newValue,
                                         sizeof(newValue))];

    return shouldBeMuted;
}


@end
