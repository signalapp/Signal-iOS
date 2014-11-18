#import "AppAudioManager.h"
#import "Environment.h"
#import "Constraints.h"
#import "RemoteIOAudio.h"
#import "ThreadManager.h"
#import "Util.h"

#define INPUT_BUS 1
#define OUTPUT_BUS 0
#define INITIAL_NUMBER_OF_BUFFERS 100
#define SAMPLE_SIZE_IN_BYTES 2

#define BUFFER_SIZE 8000

#define FLAG_MUTED    1
#define FLAG_UNMUTED  0

@interface RemoteIOAudio ()

@property (nonatomic) BOOL isStreaming;

@property (strong, nonatomic) id<AudioCallbackHandler> delegate;
@property (strong, nonatomic) id<OccurrenceLogger>     starveLogger;
@property (strong, nonatomic) id<ConditionLogger>      conditionLogger;
@property (strong, nonatomic) id<ValueLogger>          playbackBufferSizeLogger;
@property (strong, nonatomic) id<ValueLogger>          recordingQueueSizeLogger;
@property (strong, nonatomic) NSMutableSet*            unusedBuffers;

@property (readwrite, nonatomic) RemoteIOAudioState state;

@end

@implementation RemoteIOAudio

static bool doesActiveInstanceExist;

- (instancetype)initWithDelegate:(id<AudioCallbackHandler>)delegateIn untilCancelled:(TOCCancelToken*)untilCancelledToken {
    if (self = [super init]) {
        checkOperationDescribe(!doesActiveInstanceExist, @"Only one RemoteIOInterfance instance can exist at a time. Adding more will break previous instances.");
        doesActiveInstanceExist = true;
        
        self.starveLogger = [Environment.logging getOccurrenceLoggerForSender:self withKey:@"starve"];
        self.conditionLogger = [Environment.logging getConditionLoggerForSender:self];
        self.recordingQueue = [[CyclicalBuffer alloc] init];
        self.playbackQueue = [[CyclicalBuffer alloc] init];
        self.unusedBuffers = [[NSMutableSet alloc] init];
        self.state = RemoteIOAudioStateNotStarted;
        self.playbackBufferSizeLogger = [Environment.logging getValueLoggerForValue:@"|playback queue|" from:self];
        self.recordingQueueSizeLogger = [Environment.logging getValueLoggerForValue:@"|recording queue|" from:self];
        
        while (self.unusedBuffers.count < INITIAL_NUMBER_OF_BUFFERS) {
            [self addUnusedBuffer];
        }
        
        [self setupAudio];
        [self startWithDelegate:delegateIn untilCancelled:untilCancelledToken];
    }
    
    return self;
}

- (void)setupAudio {
    [[AppAudioManager sharedInstance] requestRecordingPrivlege];
    self.rioAudioUnit = [self makeAudioUnit];
    [self setAudioEnabled];
    [self setAudioStreamFormat];
    [self setAudioCallbacks];
    [self unsetAudioShouldAllocateBuffer];
    [self checkDone:AudioUnitInitialize(self.rioAudioUnit)];
}

- (AudioUnit)makeAudioUnit {
    AudioComponentDescription audioUnitDescription = [self makeAudioComponentDescription];
    AudioComponent component = AudioComponentFindNext(NULL, &audioUnitDescription);
    
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
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Input,
                                         INPUT_BUS,
                                         &enable,
                                         sizeof(enable))];
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Output,
                                         OUTPUT_BUS,
                                         &enable,
                                         sizeof(enable))];
}

- (void)setAudioStreamFormat {
    const AudioStreamBasicDescription streamDesc = [self makeAudioStreamBasicDescription];
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         OUTPUT_BUS,
                                         &streamDesc,
                                         sizeof(streamDesc))];
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
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
    d.mBytesPerFrame    = framesPerPacket*SAMPLE_SIZE_IN_BYTES;
    d.mReserved         = 0;
    d.mFormatFlags      = kAudioFormatFlagIsSignedInteger
                        | kAudioFormatFlagsNativeEndian
                        | kAudioFormatFlagIsPacked;
    return d;
}

- (void)setAudioCallbacks {
    const AURenderCallbackStruct recordingCallbackStruct = {recordingCallback, (__bridge void *)(self)};
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioOutputUnitProperty_SetInputCallback,
                                         kAudioUnitScope_Global,
                                         INPUT_BUS,
                                         &recordingCallbackStruct,
                                         sizeof(recordingCallbackStruct))];
    
    const AURenderCallbackStruct playbackCallbackStruct = {playbackCallback, (__bridge void *)(self)};
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioUnitProperty_SetRenderCallback,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &playbackCallbackStruct,
                                         sizeof(playbackCallbackStruct))];
}

- (void)unsetAudioShouldAllocateBuffer {
    const UInt32 shouldAllocateBuffer = 0;
    [self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
                                         kAudioUnitProperty_ShouldAllocateBuffer,
                                         kAudioUnitScope_Output,
                                         INPUT_BUS,
                                         &shouldAllocateBuffer,
                                         sizeof(shouldAllocateBuffer))];
}

- (RemoteIOBufferListWrapper*)addUnusedBuffer {
    RemoteIOBufferListWrapper* buf = [[RemoteIOBufferListWrapper alloc] initWithMonoBufferSize:BUFFER_SIZE];
    [self.unusedBuffers addObject:buf];
    return buf;
}

- (RemoteIOBufferListWrapper*)tryTakeUnusedBuffer {
    RemoteIOBufferListWrapper* buffer = (RemoteIOBufferListWrapper*)[self.unusedBuffers anyObject];
    if (buffer == nil) return nil;
    [self.unusedBuffers removeObject:buffer];
    return buffer;
}

- (void)returnUsedBuffer:(RemoteIOBufferListWrapper*)buffer {
    require(buffer != nil);
    if (self.state == RemoteIOAudioStateTerminated) return; // in case a buffer was in use as termination occurred
    [self.unusedBuffers addObject:buffer];
}

- (void)startWithDelegate:(id<AudioCallbackHandler>)delegateIn untilCancelled:(TOCCancelToken*)untilCancelledToken {
    require(delegateIn != nil);
    @synchronized(self){
        requireState(self.state == RemoteIOAudioStateNotStarted);
        
        self.delegate = delegateIn;
        [self checkDone:AudioOutputUnitStart(self.rioAudioUnit)];
        self.state = RemoteIOAudioStateStarted;
    }

    [untilCancelledToken whenCancelledDo:^{
        @synchronized(self) {
            self.state = RemoteIOAudioStateTerminated;
            doesActiveInstanceExist = false;
            [self checkDone:AudioOutputUnitStop(self.rioAudioUnit)];
            [[AppAudioManager sharedInstance] releaseRecordingPrivlege];
            [self.unusedBuffers removeAllObjects];
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
        
        RemoteIOAudio *instance = (__bridge RemoteIOAudio*)inRefCon;
        
        RemoteIOBufferListWrapper* buffer;
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

- (void)onRecordedDataIntoBuffer:(RemoteIOBufferListWrapper*)buffer {
    @synchronized(self) {
        if (self.state == RemoteIOAudioStateTerminated) return;
        NSData* recordedAudioVolatile = [NSData dataWithBytesNoCopy:[buffer audioBufferList]->mBuffers[0].mData
                                                             length:[buffer sampleCount]*SAMPLE_SIZE_IN_BYTES
                                                       freeWhenDone:NO];
        [self.recordingQueue enqueueData:recordedAudioVolatile];
        [self returnUsedBuffer:buffer];
    }
    
    [self.recordingQueueSizeLogger logValue:[self.recordingQueue enqueuedLength]];
    [self.delegate handleNewDataRecorded:self.recordingQueue];
}

- (void)populatePlaybackQueueWithData:(NSData*)data {
    require(data != nil);
    if (data.length == 0) return;
    @synchronized(self) {
        [self.playbackQueue enqueueData:data];
    }
}

static OSStatus playbackCallback(void *inRefCon,
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp *inTimeStamp,
                                 UInt32 inBusNumber,
                                 UInt32 inNumberSamples,
                                 AudioBufferList *ioData) {
    RemoteIOAudio* instance = (__bridge RemoteIOAudio*)inRefCon;
    NSUInteger requestedByteCount = inNumberSamples * SAMPLE_SIZE_IN_BYTES;
    NSUInteger availableByteCount;
    @synchronized(instance) {
        availableByteCount = [[instance playbackQueue] enqueuedLength];
        
        if (availableByteCount < requestedByteCount) {
            NSUInteger starveAmount = requestedByteCount - availableByteCount;
            [instance.starveLogger markOccurrence:@(starveAmount)];
        } else {
            NSData* audioToCopyVolatile = [[instance playbackQueue] dequeuePotentialyVolatileDataWithLength:requestedByteCount];
            memcpy(ioData->mBuffers[0].mData, [audioToCopyVolatile bytes], audioToCopyVolatile.length);
        }
    }
    
    [Operation asyncRun:^{[instance onRequestedPlaybackDataAmount:requestedByteCount
                                            andHadAvailableAmount:availableByteCount];}
               onThread:[ThreadManager lowLatencyThread]];
    
    if (availableByteCount < requestedByteCount) {
        return 1; // arbitrary error code
    }
    
    return noErr;
}

- (void)onRequestedPlaybackDataAmount:(NSUInteger)requestedByteCount andHadAvailableAmount:(NSUInteger)availableByteCount {
    @synchronized(self) {
        if (self.state == RemoteIOAudioStateTerminated) return;
    }
    NSUInteger consumedByteCount = availableByteCount >= requestedByteCount ? requestedByteCount : 0;
    NSUInteger remainingByteCount = availableByteCount - consumedByteCount;
    [self.playbackBufferSizeLogger logValue:remainingByteCount];
    [self.delegate handlePlaybackOccurredWithBytesRequested:requestedByteCount andBytesRemaining:remainingByteCount];
}

- (void)dealloc {
    if (self.state != RemoteIOAudioStateTerminated) {
        doesActiveInstanceExist = false;
    }
}

- (NSUInteger)getSampleRateInHertz {
    return SAMPLE_RATE;
}

- (void)checkDone:(OSStatus)resultCode {
    if (resultCode == kAudioSessionNoError) return;
    
    NSString* failure;
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
    } else if (resultCode == errSecParam){
        failure = @"oneOrMoreNonValidParameter";
    } else {
        failure = [@(resultCode) description];
    }
    [self.conditionLogger logError:[NSString stringWithFormat:@"StatusCheck failed: %@", failure]];
}

- (bool)isAudioMuted {
	UInt32 currentMuteFlag;
	UInt32 propertyByteSize;
	[self checkDone:AudioUnitGetProperty(self.rioAudioUnit,
										 kAUVoiceIOProperty_MuteOutput,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &currentMuteFlag,
										 &propertyByteSize)];
	return (FLAG_MUTED == currentMuteFlag);
}

- (BOOL)toggleMute {
	BOOL shouldBeMuted = !self.isAudioMuted;
	UInt32 newValue =  shouldBeMuted ? FLAG_MUTED : FLAG_UNMUTED;
	
	[self checkDone:AudioUnitSetProperty(self.rioAudioUnit,
										 kAUVoiceIOProperty_MuteOutput,
                                         kAudioUnitScope_Global,
                                         OUTPUT_BUS,
                                         &newValue,
										 sizeof(newValue))];
	
	return shouldBeMuted;
}

@end
