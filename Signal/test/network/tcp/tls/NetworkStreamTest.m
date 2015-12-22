#import <XCTest/XCTest.h>
#import "NetworkStream.h"
#import "TestUtil.h"

#define TEST_SERVER_HOST @"master.whispersystems.org"
#define TEST_SERVER_PORT 31337
#define TEST_SERVER_CERT_PATH @"redphone"
#define TEST_SERVER_CERT_TYPE @"cer"

#define TEST_SERVER_INCORRECT_HOST_TO_SAME_IP @"96.126.120.52"
#define TEST_SERVER_INCORRECT_CERT_PATH @"whisperFake"
#define TEST_SERVER_INCORRECT_CERT_TYPE @"cer"

@interface NetworkStreamTest : XCTestCase

@end

@interface Certificate ()
@property SecCertificateRef secCertificateRef;
@end

@implementation NetworkStreamTest

- (void)setUp{
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];
}

-(void) testReplies {
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS)];
    
    HostNameEndPoint* e = [HostNameEndPoint hostNameEndPointWithHostName:@"example.com" andPort:80];
    NetworkStream* s = [NetworkStream networkStreamToEndPoint:e];
    
    __block bool receivedReply = false;
    [s startWithHandler:[PacketHandler packetHandler:^(id packet){
        @synchronized(churnLock()) {
            receivedReply = true;
        }
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }]];
    
    [s send:[@"HEAD /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n" encodedAsUtf8]];
    
    testChurnUntil(receivedReply, 5);
    
    test(receivedReply);
    
    [s terminate];
}

-(void) testFailsOnClose {
    [Environment setCurrent:testEnvWith(ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS)];
    
    in_port_t unusedPort = 10000 + (in_port_t)arc4random_uniform(30000);
    HostNameEndPoint* e = [HostNameEndPoint hostNameEndPointWithHostName:@"localhost" andPort:unusedPort];
    NetworkStream* s = [NetworkStream networkStreamToEndPoint:e];
    
    __block bool errored = false;
    [s startWithHandler:[PacketHandler packetHandler:^(id packet){
        test(false);
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        @synchronized(churnLock()) {
            errored = true;
        }
    }]];
    
    testChurnUntil(errored, 5);
    
    test(errored);
    
    [s terminate];
}

-(void) testAuthenticationPass {
    [Environment setCurrent:testEnv];
    
    SecureEndPoint* e = [SecureEndPoint secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:TEST_SERVER_HOST andPort:TEST_SERVER_PORT]
                                      identifiedByCertificate:[Certificate certificateFromResourcePath:TEST_SERVER_CERT_PATH
                                                                                                ofType:TEST_SERVER_CERT_TYPE]];
    NetworkStream* s = [NetworkStream networkStreamToEndPoint:e];
    
    [s startWithHandler:[PacketHandler packetHandler:^(id packet) {
        test(false);
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        test(false);
    }]];
    TOCFuture* f = [s asyncConnectionCompleted];
    
    testChurnUntil(!f.isIncomplete, 5.0);
    
    test(f.hasResult && [[f forceGetResult] isEqual:@YES]);
    
    [s terminate];
}

-(void) testAuthenticationFail_WrongCert {
    [Environment setCurrent:testEnv];
    
    NSString *certPath = [[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:@"whisperFake.cer"];
    NSData *certData = [[NSData alloc] initWithContentsOfFile:certPath];
    checkOperation(certData != nil);
    
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    checkOperation(cert != nil);
    
    Certificate* instance = [Certificate new];
    instance.secCertificateRef = cert;

    SecureEndPoint* e = [SecureEndPoint secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:TEST_SERVER_HOST andPort:TEST_SERVER_PORT]
                                      identifiedByCertificate:instance];
    
    NetworkStream* s = [NetworkStream networkStreamToEndPoint:e];
    
    __block bool terminated = false;
    [s startWithHandler:[PacketHandler packetHandler:^(id packet) {
        test(false);
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        @synchronized(churnLock()) {
            terminated |= causedTermination;
        }
    }]];
    
    testChurnUntil(terminated, 5.0);
    
    test([[s asyncConnectionCompleted] hasFailed]);
    
    [s terminate];
}

-(void) testAuthenticationFail_WrongHostName {
    [Environment setCurrent:testEnv];
    
    SecureEndPoint* e = [SecureEndPoint secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:TEST_SERVER_INCORRECT_HOST_TO_SAME_IP
                                                                                                     andPort:TEST_SERVER_PORT]
                                      identifiedByCertificate:[Certificate certificateFromResourcePath:TEST_SERVER_CERT_PATH
                                                                                                ofType:TEST_SERVER_CERT_TYPE]];
    NetworkStream* s = [NetworkStream networkStreamToEndPoint:e];
    
    __block bool terminated = false;
    [s startWithHandler:[PacketHandler packetHandler:^(id packet) {
        test(false);
    } withErrorHandler:^(id error, id relatedInfo, bool causedTermination) {
        @synchronized(churnLock()) {
            terminated |= causedTermination;
        }
    }]];
    
    testChurnUntil(terminated, 5.0);
    
    test([[s asyncConnectionCompleted] hasFailed]);
    
    [s terminate];
}

@end
