#import "Environment.h"
#import "NetworkStream.h"
#import "Constraints.h"
#import "Util.h"
#import "SecureEndPoint.h"
#import "HostNameEndPoint.h"
#import "IpEndPoint.h"
#import "IpAddress.h"
#import "ThreadManager.h"

#define READ_BUFFER_LENGTH 1024

@implementation NetworkStream

+(NetworkStream*) networkStreamToEndPoint:(id<NetworkEndPoint>)remoteEndPoint {
    require(remoteEndPoint != nil);
    
    // all connections must be secure, unless testing
    bool isSecureEndPoint = [remoteEndPoint isKindOfClass:[SecureEndPoint class]];
    bool allowTestNonSecure = [Environment hasEnabledTestingOrLegacyOption:ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS];
    require(allowTestNonSecure || isSecureEndPoint);
    
    StreamPair* streams = [remoteEndPoint createStreamPair];
    
    NetworkStream* s = [NetworkStream new];
    s->readBuffer = [NSMutableData dataWithLength:READ_BUFFER_LENGTH];
    s->inputStream = [streams inputStream];
    s->outputStream = [streams outputStream];
    s->writeBuffer = [CyclicalBuffer new];
    s->remoteEndPoint = remoteEndPoint;
    s->futureOpenedSource = [FutureSource new];
    s->futureConnectedAndWritableSource = [FutureSource new];
    s->runLoop = [ThreadManager normalLatencyThreadRunLoop];
    [s->inputStream scheduleInRunLoop:s->runLoop forMode:NSDefaultRunLoopMode];
    [s->outputStream scheduleInRunLoop:s->runLoop forMode:NSDefaultRunLoopMode];
    
    [s->futureConnectedAndWritableSource catchDo:^(id error) {
        @synchronized(self) {
            [s onNetworkFailure:error];
        }
    }];
    
    
    [s->inputStream setDelegate:s];
    [s->outputStream setDelegate:s];
    
    return s;
}

-(Future*) asyncConnectionCompleted { return futureConnectedAndWritableSource; }
-(Future*) asyncTcpHandshakeCompleted { return futureOpenedSource; }

-(void) terminate {
    @synchronized(self) {
        if (closedLocally) return;
        closedLocally = true;
        [futureConnectedAndWritableSource trySetResult:@NO]; // did not connect, no error
        [futureOpenedSource trySetResult:@NO];
        [inputStream close];
        [outputStream close];
    }
}
-(void) send:(NSData*)data {
    require(data != nil);
    requireState(rawDataHandler != nil);
    @synchronized(self) {
        [writeBuffer enqueueData:data];
        [self tryWriteBufferedData];
    }
}
-(void) tryWriteBufferedData {
    if (![futureConnectedAndWritableSource hasSucceeded]) return;
    if (![[futureConnectedAndWritableSource forceGetResult] isEqual:@YES]) return;
    NSStreamStatus status = [outputStream streamStatus];
    if (status < NSStreamStatusOpen) return;
    if (status >= NSStreamStatusAtEnd) {
        [rawDataHandler handleError:@"Wrote to ended/closed/errored stream."
                        relatedInfo:nil
                  causedTermination:false];
        return;
    }
    
    while ([writeBuffer enqueuedLength] > 0 && [outputStream hasSpaceAvailable]) {
        NSData* data = [writeBuffer peekVolatileHeadOfData];
        NSInteger d = [outputStream write:[data bytes] maxLength:data.length];
        
        // reached destination buffer capacity?
        if (d == 0) break;
        
        if (d < 0) {
            id error = [outputStream streamError];
            if (error == nil){
                error = @"Unknown error when writing to stream.";
            }
            [rawDataHandler handleError:error relatedInfo:nil causedTermination:false];
            return;
        }
        
        // written, discard
        [writeBuffer discard:(NSUInteger)d];
    }
}
-(void) startWithHandler:(PacketHandler*)handler {
    require(handler != nil);
    requireState(rawDataHandler == nil);
    @synchronized(self) {
        rawDataHandler = handler;
        [self startProcessingStreamEventsEvenWithoutHandler];
    }
}
-(void) startProcessingStreamEventsEvenWithoutHandler {
    @synchronized(self) {
        if (started) return;
        started = true;
        
        [inputStream open];
        [outputStream open];
    }
}


-(void) onNetworkFailure:(id)error {
    @synchronized(self) {
        [futureOpenedSource trySetFailure:error];
        [futureConnectedAndWritableSource trySetFailure:error];
        [rawDataHandler handleError:error relatedInfo:nil causedTermination:true];
        DDLogError(@"Network failure happened on network stream: %@", error);
        [self terminate];
    }
}

-(void) onOpenCompleted {
    if (![futureOpenedSource trySetResult:@YES]) return;
    
    @try {
        [remoteEndPoint handleStreamsOpened:[StreamPair streamPairWithInput:inputStream
                                                                  andOutput:outputStream]];
    } @catch (OperationFailed* ex) {
        [self onNetworkFailure:ex];
    }
}

-(void) onSpaceAvailableToWrite {
    [self tryWriteBufferedData];
    
    if ([futureConnectedAndWritableSource isCompletedOrWiredToComplete]) return;
    
    Future* checked = [remoteEndPoint asyncHandleStreamsConnected:[StreamPair streamPairWithInput:inputStream
                                                                                        andOutput:outputStream]];
    [futureConnectedAndWritableSource trySetResult:checked];
    [futureConnectedAndWritableSource thenDo:^(id result) {
        @synchronized(self) {
            [self onSpaceAvailableToWrite];
        }
    }];
    [futureConnectedAndWritableSource catchDo:^(id error) {
        @synchronized(self) {
            [self onNetworkFailure:error];
        }
    }];
}

-(void) onErrorOccurred:(id)fallbackError {
    NSError *error;
    
    DDLogError(@"Stream status: %@", self.description);
    
    if ([inputStream streamError]) {
        error = [inputStream streamError];
        DDLogError(@"Error on incoming stream : %@", error);
    } else if ([outputStream streamError]){
        error = [outputStream streamError];
        DDLogError(@"Error on outgoing stream: %@", error);
    } else{
        error = fallbackError;
        DDLogError(@"Fallback error: %@", fallbackError);
    }
    [self onNetworkFailure:error];
}

-(void) onBytesAvailableToRead {
    if (rawDataHandler == nil) return;
    if (![futureConnectedAndWritableSource hasSucceeded]) return;
    if (![[futureConnectedAndWritableSource forceGetResult] isEqual:@YES]) return;
    
    while ([inputStream hasBytesAvailable]) {
        NSInteger numRead = [inputStream read:[readBuffer mutableBytes] maxLength:readBuffer.length];
        
        if (numRead < 0) [self onErrorOccurred:@"Read Error"];
        if (numRead <= 0) break;
        
        NSData* readData = [readBuffer take:(NSUInteger)numRead];
        [rawDataHandler handlePacket:readData];
    }
}

-(void) onEndOfStream {
    [self onBytesAvailableToRead];
    if (!closedLocally) {
        [self onErrorOccurred:@"Closed Remotely."];
    }
    [self terminate];
}

-(void)stream:(NSStream*)aStream handleEvent:(NSStreamEvent)event {
    requireState(aStream == inputStream || aStream == outputStream);
    bool isInputStream = aStream == inputStream;
    
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

-(NSString *)description {
    NSString* status = @"Not Started";
    if (started) status = @"Connecting";
    if ([futureOpenedSource hasSucceeded]) status = @"Connecting (TCP Handshake Completed)";
    if ([futureConnectedAndWritableSource hasSucceeded]) status = @"Connected";
    if (closedLocally) status = @"Closed";
    if ([futureConnectedAndWritableSource hasFailed]) status = @"Failed";
    
    return [NSString stringWithFormat:@"Status: %@, RemoteEndPoint: %@",
            status,
            remoteEndPoint];
}

@end
