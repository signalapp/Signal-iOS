#import <XCTest/XCTest.h>
#import "DnsManager.h"
#import "TestUtil.h"
#import "Util.h"
#import "IpAddress.h"
#import "ThreadManager.h"
#import "CancelTokenSource.h"
#import <netdb.h>

#define infrastructureTestHostName @"relay.whispersystems.org"
#define reliableHostName @"example.com"
#define invalidHostname @"∆©˙∆¨¥©©˜¨¥©˜†¥µ¬¬¨˙µ†¥∫®∂®†"
#define nonExistentHostname [NSString stringWithFormat:@"%@kfurmtludehntlgihmvnduyebntiinvbudydepqowudyfnrkt.com", \
    [[CryptoTools generateSecureRandomData:10] encodedAsBase64]]

@interface DnsManagerTest : XCTestCase

@end

@implementation DnsManagerTest

-(void) testQueryAddresses_Sequential {
    Future* f1 = [DnsManager asyncQueryAddressesForDomainName:reliableHostName
                                              unlessCancelled:nil];
    testChurnUntil(f1.hasSucceeded, 5.0);
    test([(NSArray*)[f1 forceGetResult] count] > 0);

    Future* f2 = [DnsManager asyncQueryAddressesForDomainName:invalidHostname
                                              unlessCancelled:nil];
    testChurnUntil(f2.hasFailed, 5.0);

    Future* f3 = [DnsManager asyncQueryAddressesForDomainName:nonExistentHostname
                                              unlessCancelled:nil];
    testChurnUntil(f3.hasFailed, 5.0);

    Future* f4 = [DnsManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                              unlessCancelled:nil];
    testChurnUntil(f4.hasSucceeded, 5.0);
    test(f4.hasSucceeded && [(NSArray*)[f4 forceGetResult] count] > 0);
    
}

-(void) testQueryAddresses_Concurrent {
    Future* f1 = [DnsManager asyncQueryAddressesForDomainName:reliableHostName
                                                 unlessCancelled:nil];
    Future* f2 = [DnsManager asyncQueryAddressesForDomainName:invalidHostname
                                              unlessCancelled:nil];
    Future* f3 = [DnsManager asyncQueryAddressesForDomainName:nonExistentHostname
                                              unlessCancelled:nil];
    Future* f4 = [DnsManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                              unlessCancelled:nil];
    
    testChurnUntil(f1.hasSucceeded && f2.hasFailed && f3.hasFailed && f4.hasSucceeded, 5.0);
    test(f1.hasSucceeded && [(NSArray*)[f1 forceGetResult] count] > 0);
    test(f4.hasSucceeded && [(NSArray*)[f4 forceGetResult] count] > 0);
}

-(void) testQueryAddresses_Cancel {
    CancelTokenSource* c = [CancelTokenSource cancelTokenSource];
    Future* f1 = [DnsManager asyncQueryAddressesForDomainName:reliableHostName
                                              unlessCancelled:[c getToken]];
    Future* f2 = [DnsManager asyncQueryAddressesForDomainName:invalidHostname
                                              unlessCancelled:[c getToken]];
    Future* f3 = [DnsManager asyncQueryAddressesForDomainName:nonExistentHostname
                                              unlessCancelled:[c getToken]];
    Future* f4 = [DnsManager asyncQueryAddressesForDomainName:infrastructureTestHostName
                                              unlessCancelled:[c getToken]];
    [c cancel];
    
    testChurnUntil(!f1.isIncomplete && f2.hasFailed && f3.hasFailed && !f4.isIncomplete, 5.0);
    test(f1.hasSucceeded || [[f1 forceGetFailure] conformsToProtocol:@protocol(CancelToken)]);
    test(f2.hasFailed);
    test(f3.hasFailed);
    test(f4.hasSucceeded || [[f4 forceGetFailure] conformsToProtocol:@protocol(CancelToken)]);
}

-(void)testQueryAddresses_FastCancel {
    CancelTokenSource* c = [CancelTokenSource cancelTokenSource];
    Future* f = [DnsManager asyncQueryAddressesForDomainName:reliableHostName
                                             unlessCancelled:[c getToken]];
    [c cancel];
    test(!f.isIncomplete);
}

@end
