#import <XCTest/XCTest.h>
#import "DNSManager.h"
#import "TestUtil.h"
#import "Util.h"
#import "IPAddress.h"
#import "ThreadManager.h"
#import <netdb.h>

#define infrastructureTestHostName @"relay.whispersystems.org"
#define reliableHostName @"example.com"
#define invalidHostname @"∆©˙∆¨¥©©˜¨¥©˜†¥µ¬¬¨˙µ†¥∫®∂®†"
#define nonExistentHostname [NSString stringWithFormat:@"%@kfurmtludehntlgihmvnduyebntiinvbudydepqowudyfnrkt.com", \
    [[CryptoTools generateSecureRandomData:10] encodedAsBase64]]

@interface DNSManagerTest : XCTestCase

@end

@implementation DNSManagerTest

-(void) testQueryAddresses_Sequential {
    TOCFuture* f1 = [DNSManager asyncQueryAddressesForDomainName:reliableHostName
                                                 unlessCancelled:nil];
    testChurnUntil(f1.hasResult, 5.0);
    test(f1.hasResult && [(NSArray*)[f1 forceGetResult] count] > 0);
    
    TOCFuture* f2 = [DNSManager asyncQueryAddressesForDomainName:invalidHostname
                                                 unlessCancelled:nil];
    testChurnUntil(f2.hasFailed, 5.0);
    
    TOCFuture* f3 = [DNSManager asyncQueryAddressesForDomainName:nonExistentHostname
                                                 unlessCancelled:nil];
    testChurnUntil(f3.hasFailed, 5.0);
    
    TOCFuture* f4 = [DNSManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                                 unlessCancelled:nil];
    testChurnUntil(f4.hasResult, 5.0);
    test(f4.hasResult && [(NSArray*)[f4 forceGetResult] count] > 0);
    
}

-(void) testQueryAddresses_Concurrent {
    TOCFuture* f1 = [DNSManager asyncQueryAddressesForDomainName:reliableHostName
                                                 unlessCancelled:nil];
    TOCFuture* f2 = [DNSManager asyncQueryAddressesForDomainName:invalidHostname
                                                 unlessCancelled:nil];
    TOCFuture* f3 = [DNSManager asyncQueryAddressesForDomainName:nonExistentHostname
                                                 unlessCancelled:nil];
    TOCFuture* f4 = [DNSManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                                 unlessCancelled:nil];
    
    testChurnUntil(f1.hasResult && f2.hasFailed && f3.hasFailed && f4.hasResult, 5.0);
    test(f1.hasResult && [(NSArray*)[f1 forceGetResult] count] > 0);
    test(f4.hasResult && [(NSArray*)[f4 forceGetResult] count] > 0);
}

-(void) testQueryAddresses_Cancel {
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    TOCFuture* f1 = [DNSManager asyncQueryAddressesForDomainName:reliableHostName
                                                 unlessCancelled:c.token];
    TOCFuture* f2 = [DNSManager asyncQueryAddressesForDomainName:invalidHostname
                                                 unlessCancelled:c.token];
    TOCFuture* f3 = [DNSManager asyncQueryAddressesForDomainName:nonExistentHostname
                                                 unlessCancelled:c.token];
    TOCFuture* f4 = [DNSManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                                 unlessCancelled:c.token];
    [c cancel];
    
    testChurnUntil(!f1.isIncomplete && f2.hasFailed && f3.hasFailed && !f4.isIncomplete, 5.0);
    test(f1.hasResult || f1.hasFailedWithCancel);
    test(f2.hasFailed);
    test(f3.hasFailed);
    test(f4.hasResult || f4.hasFailedWithCancel);
}

-(void)testQueryAddresses_FastCancel {
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    TOCFuture* f = [DNSManager asyncQueryAddressesForDomainName:reliableHostName
                                                unlessCancelled:c.token];
    [c cancel];
    test(!f.isIncomplete);
}

@end
