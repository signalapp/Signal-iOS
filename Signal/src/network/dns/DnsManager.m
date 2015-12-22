#import "DnsManager.h"

#import <netdb.h>
#import "IpEndPoint.h"
#import "ThreadManager.h"
#import "Util.h"

#define STRING_POINTER_FLAG 0xc0

#define gethostbyname_ErrorDescriptions @{ \
    @HOST_NOT_FOUND: @"HOST_NOT_FOUND. The specified host is unknown.", \
    @NO_ADDRESS: @"NO_ADDRESS. The requested name is valid but does not have an IP address.",  \
    @NO_DATA: @"NO_DATA. The requested name is valid but does not have an IP address.",  \
    @NO_RECOVERY: @"NO_RECOVERY. A nonrecoverable name server error occurred.",  \
    @TRY_AGAIN: @"TRY_AGAIN. A temporary error occurred on an authoritative name server."  \
}

@implementation DnsManager

void handleDnsCompleted(CFHostRef, CFHostInfoType, const CFStreamError*, void*);
void handleDnsCompleted(CFHostRef hostRef, CFHostInfoType typeInfo, const CFStreamError* error, void* info) {
    DnsManager* instance = (__bridge_transfer DnsManager*)info;
    
    @try {
        Boolean gotHostAddressesData = false;
        NSArray* addressDatas = (__bridge NSArray*)CFHostGetAddressing(hostRef, &gotHostAddressesData);
        checkOperation(gotHostAddressesData);
        checkOperationDescribe(addressDatas != nil, @"No addresses for host");
        
        NSArray* ips = [addressDatas map:^(id addressData) {
            checkOperation([addressData isKindOfClass:NSData.class]);
            
            return [[IpEndPoint ipEndPointFromSockaddrData:addressData] address];
        }];
        
        [instance->futureResultSource trySetResult:ips];
    } @catch (OperationFailed* ex) {
        [instance->futureResultSource trySetFailure:ex];
    }
}

+(TOCFuture*) asyncQueryAddressesForDomainName:(NSString*)domainName
                               unlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    ows_require(domainName != nil);
    
    CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)domainName);
    checkOperation(hostRef != nil);
    
    DnsManager* d = [DnsManager new];
    d->futureResultSource = [TOCFutureSource futureSourceUntil:unlessCancelledToken];
    
    CFHostClientContext c;
    c.version = 0;
    c.info = (__bridge_retained void*)d;
    c.release = CFRelease;
    c.retain = CFRetain;
    c.copyDescription = CFCopyDescription;
    
    CFHostSetClient(hostRef, handleDnsCompleted, &c);
    CFHostScheduleWithRunLoop(hostRef,
                              [[ThreadManager normalLatencyThreadRunLoop] getCFRunLoop],
                              kCFRunLoopDefaultMode);
    
    Boolean startedSuccess = CFHostStartInfoResolution(hostRef, kCFHostAddresses, &d->error);
    CFRelease(hostRef);
    if (!startedSuccess) {
        [d->futureResultSource trySetFailure:[OperationFailed new:[NSString stringWithFormat:@"DNS query failed to start. Error code: %d",
                                                                   (int)d->error.error]]];
    }
    
    return d->futureResultSource.future;
}

@end
