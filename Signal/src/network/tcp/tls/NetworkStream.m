#import "Environment.h"
#import "NetworkStream.h"
#import "Constraints.h"
#import "Util.h"
#import "SecureEndPoint.h"
#import "HostNameEndPoint.h"
#import "IPEndPoint.h"
#import "IPAddress.h"
#import "ThreadManager.h"

#define READ_BUFFER_LENGTH 1024

@interface NetworkStream ()

@property (strong, nonatomic) NSMutableData* readBuffer;
@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;
@property (strong, nonatomic) PacketHandler* rawDataHandler;
@property (strong, nonatomic) CyclicalBuffer* writeBuffer;
@property (strong, nonatomic) TOCFutureSource* futureConnectedAndWritableSource;
@property (strong, nonatomic) TOCFutureSource* futureOpenedSource;
@property (strong, nonatomic) id<NetworkEndPoint> remoteEndPoint;
@property (strong, nonatomic) NSRunLoop* runLoop;
@property (nonatomic) bool started;
@property (nonatomic) bool closedLocally;

@end

@implementation NetworkStream

- (instancetype)initWithRemoteEndPoint:(id<NetworkEndPoint>)remoteEndPoint {
    if (self = [super init]) {
        require(remoteEndPoint != nil);
        
        // all connections must be secure, unless testing
        bool isSecureEndPoint = [remoteEndPoint isKindOfClass:[SecureEndPoint class]];
        bool allowTestNonSecure = [Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS];
        require(allowTestNonSecure || isSecureEndPoint);
        
        StreamPair* streams = [remoteEndPoint createStreamPair];
        
        self.readBuffer = [NSMutableData dataWithLength:READ_BUFFER_LENGTH];
        self.inputStream = streams.inputStream;
        self.outputStream = streams.outputStream;
        self.writeBuffer = [[CyclicalBuffer alloc] init];
        self.remoteEndPoint = remoteEndPoint;
        self.futureOpenedSource = [[TOCFutureSource alloc] init];
        self.futureConnectedAndWritableSource = [[TOCFutureSource alloc] init];
        self.runLoop = [ThreadManager normalLatencyThreadRunLoop];
        [self.inputStream scheduleInRunLoop:self.runLoop forMode:NSDefaultRunLoopMode];
        [self.outputStream scheduleInRunLoop:self.runLoop forMode:NSDefaultRunLoopMode];
        
        [self.futureConnectedAndWritableSource.future catchDo:^(id error) {
            @synchronized(self) {
                [self onNetworkFailure:error];
            }
        }];
        
        [self.inputStream setDelegate:self];
        [self.outputStream setDelegate:self];
    }
    
    return self;
}

- (TOCFuture*)asyncConnectionCompleted {
    return self.futureConnectedAndWritableSource.future;
}

- (TOCFuture*)asyncTCPHandshakeCompleted {
    return self.futureOpenedSource.future;
}

- (void)terminate {
    @synchronized(self) {
        if (self.closedLocally) return;
        self.closedLocally = true;
        [self.futureConnectedAndWritableSource trySetResult:@NO]; // did not connect, no error
        [self.futureOpenedSource trySetResult:@NO];
        [self.inputStream close];
        [self.outputStream close];
    }
}

- (void)send:(NSData*)data {
    require(data != nil);
    requireState(self.rawDataHandler != nil);
    @synchronized(self) {
        [self.writeBuffer enqueueData:data];
        [self tryWriteBufferedData];
    }
}

- (void)tryWriteBufferedData {
    if (!self.futureConnectedAndWritableSource.future.hasResult) return;
    if (![[self.futureConnectedAndWritableSource.future forceGetResult] isEqual:@YES]) return;
    NSStreamStatus status = [self.outputStream streamStatus];
    if (status < NSStreamStatusOpen) return;
    if (status >= NSStreamStatusAtEnd) {
        [self.rawDataHandler handleError:@"Wrote to ended/closed/errored stream."
                             relatedInfo:nil
                       causedTermination:false];
        return;
    }
    
    while ([self.writeBuffer enqueuedLength] > 0 && self.outputStream.hasSpaceAvailable) {
        NSData* data = [self.writeBuffer peekVolatileHeadOfData];
        NSInteger d = [self.outputStream write:[data bytes] maxLength:data.length];
        
        // reached destination buffer capacity?
        if (d == 0) break;
        
        if (d < 0) {
            id error = [self.outputStream streamError];
            if (error == nil){
                error = @"Unknown error when writing to stream.";
            }
            [self.rawDataHandler handleError:error relatedInfo:nil causedTermination:false];
            return;
        }
        
        // written, discard
        [self.writeBuffer discard:(NSUInteger)d];
    }
}

- (void)startWithHandler:(PacketHandler*)handler {
    require(handler != nil);
    requireState(self.rawDataHandler == nil);
    @synchronized(self) {
        self.rawDataHandler = handler;
        [self startProcessingStreamEventsEvenWithoutHandler];
    }
}

- (void)startProcessingStreamEventsEvenWithoutHandler {
    @synchronized(self) {
        if (self.started) return;
        self.started = true;
        
        [self.inputStream open];
        [self.outputStream open];
    }
}

- (void)onNetworkFailure:(id)error {
    @synchronized(self) {
        [self.futureOpenedSource trySetFailure:error];
        [self.futureConnectedAndWritableSource trySetFailure:error];
        [self.rawDataHandler handleError:error relatedInfo:nil causedTermination:true];
        DDLogError(@"Network failure happened on network stream: %@", error);
        [self terminate];
    }
}

- (void)onOpenCompleted {
    if (![self.futureOpenedSource trySetResult:@YES]) return;
    
    @try {
        [self.remoteEndPoint handleStreamsOpened:[[StreamPair alloc] initWithInput:self.inputStream
                                                                         andOutput:self.outputStream]];
    } @catch (OperationFailed* ex) {
        [self onNetworkFailure:ex];
    }
}

- (void)onSpaceAvailableToWrite {
    [self tryWriteBufferedData];
    
    if (self.futureConnectedAndWritableSource.future.state != TOCFutureState_AbleToBeSet) return;
    
    TOCFuture* checked = [self.remoteEndPoint asyncHandleStreamsConnected:[[StreamPair alloc] initWithInput:self.inputStream
                                                                                                  andOutput:self.outputStream]];
    [self.futureConnectedAndWritableSource trySetResult:checked];
    [self.futureConnectedAndWritableSource.future thenDo:^(id result) {
        @synchronized(self) {
            [self onSpaceAvailableToWrite];
        }
    }];
    [self.futureConnectedAndWritableSource.future catchDo:^(id error) {
        @synchronized(self) {
            [self onNetworkFailure:error];
        }
    }];
}

- (void)onErrorOccurred:(id)fallbackError {
    NSError *error;
    
    DDLogError(@"Stream status: %@", self.description);
    
    if ([self.inputStream streamError]) {
        error = [self.inputStream streamError];
        DDLogError(@"Error on incoming stream : %@", error);
    } else if ([self.outputStream streamError]) {
        error = [self.outputStream streamError];
        DDLogError(@"Error on outgoing stream: %@", error);
    } else {
        error = fallbackError;
        DDLogError(@"Fallback error: %@", fallbackError);
    }
    [self onNetworkFailure:error];
}

- (void)onBytesAvailableToRead {
    if (self.rawDataHandler == nil) return;
    if (!self.futureConnectedAndWritableSource.future.hasResult) return;
    if (![self.futureConnectedAndWritableSource.future.forceGetResult isEqual:@YES]) return;
    
    while (self.inputStream.hasBytesAvailable) {
        NSInteger numRead = [self.inputStream read:[self.readBuffer mutableBytes] maxLength:self.readBuffer.length];
        
        if (numRead < 0) [self onErrorOccurred:@"Read Error"];
        if (numRead <= 0) break;
        
        NSData* readData = [self.readBuffer take:(NSUInteger)numRead];
        [self.rawDataHandler handlePacket:readData];
    }
}

- (void)onEndOfStream {
    [self onBytesAvailableToRead];
    if (!self.closedLocally) {
        [self onErrorOccurred:@"Closed Remotely."];
    }
    [self terminate];
}

- (void)stream:(NSStream*)aStream handleEvent:(NSStreamEvent)event {
    requireState(aStream == self.inputStream || aStream == self.outputStream);
    bool isInputStream = aStream == self.inputStream;
    
    @synchronized(self) {
        switch(event) {
            case NSStreamEventOpenCompleted:
                [self onOpenCompleted];
                break;
                
            case NSStreamEventHasBytesAvailable:
                [self onBytesAvailableToRead];
                break;
                
            case NSStreamEventHasSpaceAvailable:
                [self onSpaceAvailableToWrite];
                break;
                
            case NSStreamEventErrorOccurred:
                [self onErrorOccurred:[NSString stringWithFormat:@"Unknown %@ stream error.",
                                       isInputStream ? @"input" : @"output"]];
                break;
                
            case NSStreamEventEndEncountered:
                [self onEndOfStream];
                break;
                
            default:
                [self onErrorOccurred:[NSString stringWithFormat:@"Unexpected %@ stream event: %lu.",
                                       isInputStream ? @"input" : @"output",
                                       (unsigned long)event]];
        }
    }
}

- (NSString*)description {
    NSString* status = @"Not Started";
    if (self.started) status = @"Connecting";
    if (self.futureOpenedSource.future.hasResult) status = @"Connecting (TCP Handshake Completed)";
    if (self.futureConnectedAndWritableSource.future.hasResult) status = @"Connected";
    if (self.closedLocally) status = @"Closed";
    if (self.futureConnectedAndWritableSource.future.hasFailed) status = @"Failed";
    
    return [NSString stringWithFormat:@"Status: %@, RemoteEndPoint: %@",
            status,
            self.remoteEndPoint];
}

@end
