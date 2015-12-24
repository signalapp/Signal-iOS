#import <XCTest/XCTest.h>
#import "InitiatorSessionDescriptor.h"
#import "ResponderSessionDescriptor.h"
#import "SignalKeyingStorage.h"
#import "TestUtil.h"

@interface SignalKeyingStorage ()
+ (void)storeData:(NSData *)data forKey:(NSString *)key;
@end

@interface SessionDescriptorTest : XCTestCase

@end

@implementation SessionDescriptorTest

- (void)testInitiatorSessionDescriptionJson {
    InitiatorSessionDescriptor *d = [InitiatorSessionDescriptor initiatorSessionDescriptorWithSessionId:5
                                                                                     andRelayServerName:@"example.com"
                                                                                           andRelayPort:6];
    test([d sessionId] == 5);
    test([d relayUdpPort] == 6);
    test([d.relayServerName isEqualToString:@"example.com"]);

    // roundtrip
    InitiatorSessionDescriptor *d2 = [InitiatorSessionDescriptor initiatorSessionDescriptorFromJson:d.toJson];
    test([d2 sessionId] == 5);
    test([d2 relayUdpPort] == 6);
    test([d2.relayServerName isEqualToString:@"example.com"]);

    // constant
    InitiatorSessionDescriptor *d3 = [InitiatorSessionDescriptor
        initiatorSessionDescriptorFromJson:@"{\"sessionId\":5,\"serverName\":\"example.com\",\"relayPort\":6}"];
    test([d3 sessionId] == 5);
    test([d3 relayUdpPort] == 6);
    test([d3.relayServerName isEqualToString:@"example.com"]);
}

- (void)testResponderSessionDescriptorFromEncryptedRemoteNotification2 {
    NSDictionary *notification = @{
        @"aps" : @{@"alert" : @"Incoming Call!"},
        @"m" : @"AJV74NzwSbZ1KeV4pRwPfMZQ3a5n0V0/HV7eABUUCJvRVqGe3qFO/2XHKv1nEDwNg2naQDmd/nLOlvk="
    };

    [Environment setCurrent:testEnv];
    [[TSStorageManager sharedManager] setupDatabase];

    [SignalKeyingStorage storeData:[@"0000000000000000000000000000000000000000" decodedAsHexString]
                            forKey:SIGNALING_MAC_KEY];
    [SignalKeyingStorage storeData:[@"00000000000000000000000000000000" decodedAsHexString]
                            forKey:SIGNALING_CIPHER_KEY];

    ResponderSessionDescriptor *d =
        [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:notification];

    test(d.interopVersion == 1);
    test(d.relayUdpPort == 11235);
    test(d.sessionId == 2357);
    test([d.relayServerName isEqualToString:@"Test"]);
    test([d.initiatorNumber.toE164 isEqualToString:@"+19027777777"]);
}

@end
