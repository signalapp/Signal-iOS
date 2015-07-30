#import <XCTest/XCTest.h>
#import "LowLatencyConnector.h"
#import "Util.h"
#import "HostNameEndPoint.h"
#import "TestUtil.h"

@interface LowLatencyConnectorTest : XCTestCase
@end

@implementation LowLatencyConnectorTest

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
}

-(void) testLowLatencyConnect_example {
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS)];

    NSString* reliableHostName = @"example.com";
    
    TOCFuture* f = [LowLatencyConnector asyncLowLatencyConnectToEndPoint:[HostNameEndPoint hostNameEndPointWithHostName:reliableHostName
                                                                                                                andPort:80]
                                                          untilCancelled:nil];
    
    testChurnUntil(!f.isIncomplete, 5.0);
    
    LowLatencyCandidate* r = [f forceGetResult];
    NetworkStream* channel = [r networkStream];
    
    // --- attempt to actually use the streams ---
    __block NSString* response = nil;
    PacketHandler* h = [PacketHandler packetHandler:^(id packet) {
        @synchronized(churnLock()) {
            response = [packet decodedAsUtf8];
        }
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }];
    [channel startWithHandler:h];
    [channel send:[@"HEAD /index.html HTTP/1.1\r\nHost: www.example.com\r\n\r\n" encodedAsUtf8]];
    
    testChurnUntil(response != nil, 5.0);
    test([response hasPrefix:@"HTTP"]);
    
    [channel terminate];
}
-(void) testLowLatencyConnect_google {
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS)];
    
    NSString* reliableHostNameKnownToHaveMultipleIps = @"google.com";
    
    TOCFuture* f = [LowLatencyConnector asyncLowLatencyConnectToEndPoint:[HostNameEndPoint hostNameEndPointWithHostName:reliableHostNameKnownToHaveMultipleIps
                                                                                                                andPort:80]
                                                          untilCancelled:nil];
    
    testChurnUntil(!f.isIncomplete, 5.0);
    
    LowLatencyCandidate* r = [f forceGetResult];
    NetworkStream* channel = [r networkStream];
    
    // --- attempt to actually use the streams ---
    __block NSString* response = nil;
    PacketHandler* h = [PacketHandler packetHandler:^(id packet) {
        @synchronized(churnLock()) {
            response = [packet decodedAsUtf8];
        }
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }];
    [channel startWithHandler:h];
    [channel send:[@"HEAD /index.html HTTP/1.1\r\nHost: www.example.com\r\n\r\n" encodedAsUtf8]];
    
    testChurnUntil(response != nil, 5.0);
    test([response hasPrefix:@"HTTP"]);
    
    [channel terminate];
}

-(void) testCancelledLowLatencyConnect {
    NSString* reliableHostName = @"example.com";
    
    TOCFuture* f = [LowLatencyConnector asyncLowLatencyConnectToEndPoint:[HostNameEndPoint hostNameEndPointWithHostName:reliableHostName andPort:80]
                                                          untilCancelled:TOCCancelToken.cancelledToken];
    
    testChurnUntil(!f.isIncomplete, 5.0);
    
    test(f.hasFailed);
}

@end
