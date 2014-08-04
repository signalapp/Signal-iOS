#import <XCTest/XCTest.h>
#import "InitiatorSessionDescriptor.h"
#import "ResponderSessionDescriptor.h"
#import "TestUtil.h"
#import "Util.h"
#import <UICKeyChainStore/UICKeyChainStore.h>

@interface SessionDescriptorTest : XCTestCase

@end

@implementation SessionDescriptorTest

-(void) testInitiatorSessionDescriptionJson {
    InitiatorSessionDescriptor* d = [InitiatorSessionDescriptor initiatorSessionDescriptorWithSessionId:5
                                                                                     andRelayServerName:@"example.com"
                                                                                           andRelayPort:6];
    test([d sessionId] == 5);
    test([d relayUdpPort] == 6);
    test([[d relayServerName] isEqualToString:@"example.com"]);
    
    // roundtrip
    InitiatorSessionDescriptor* d2 = [InitiatorSessionDescriptor initiatorSessionDescriptorFromJson:[d toJson]];
    test([d2 sessionId] == 5);
    test([d2 relayUdpPort] == 6);
    test([[d2 relayServerName] isEqualToString:@"example.com"]);
    
    // constant
    InitiatorSessionDescriptor* d3 = [InitiatorSessionDescriptor initiatorSessionDescriptorFromJson:@"{\"sessionId\":5,\"serverName\":\"example.com\",\"relayPort\":6}"];
    test([d3 sessionId] == 5);
    test([d3 relayUdpPort] == 6);
    test([[d3 relayServerName] isEqualToString:@"example.com"]);
}

-(void) testResponderSessionDescriptorFromEncryptedRemoteNotification2 {


    // todo: Rewrite test to support keychain storage with NSData
    
//    NSDictionary* notification = @{
//                                   @"aps":@{@"alert":@"Incoming Call!"},
//                                   @"m":@"AJV74NzwSbZ1KeV4pRwPfMZQ3a5n0V0/HV7eABUUCJvRVqGe3qFO/2XHKv1nEDwNg2naQDmd/nLOlvk="
//                                   };
//    
//    [Environment setCurrent:testEnv];
//    [[UICKeyChainStore keyChainStore]setValue:[@"0000000000000000000000000000000000000000" decodedAsHexString]forKey:@"Signaling Mac Key"];
//
//    [[UICKeyChainStore keyChainStore] setValue:[@"00000000000000000000000000000000" decodedAsHexString] forKey:@"Signaling Cipher Key"];
//    
//    ResponderSessionDescriptor* d = [ResponderSessionDescriptor responderSessionDescriptorFromEncryptedRemoteNotification:notification];
//  
//    test(d.interopVersion == 1);
//    test(d.relayUdpPort == 11235);
//    test(d.sessionId == 2357);
//    test([d.relayServerName isEqualToString:@"Test"]);
//    test([[d.initiatorNumber toE164] isEqualToString:@"+19027777777"]);
}

@end
