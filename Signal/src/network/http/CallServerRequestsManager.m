#import "HttpRequest.h"
#import "CallServerRequestsManager.h"
#import "DataUtil.h"
#import "Environment.h"
#import "HostNameEndPoint.h"
#import "SGNKeychainUtil.h"

#define defaultRequestTimeout

@interface CallServerRequestsManager ()

@property (nonatomic, retain)AFHTTPSessionManager *operationManager;

@end


@implementation CallServerRequestsManager

MacrosSingletonImplemention

- (id)init{
    self = [super init];
    
    if (self) {
        HostNameEndPoint *endpoint = [[[Environment getCurrent]masterServerSecureEndPoint] hostNameEndPoint];
        NSURL *endPointURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@:%hu", endpoint.hostname, endpoint.port]];
        NSURLSessionConfiguration *sessionConf = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        self.operationManager = [[AFHTTPSessionManager alloc] initWithBaseURL:endPointURL sessionConfiguration:sessionConf];
        self.operationManager.responseSerializer                      = [AFJSONResponseSerializer serializer];
        self.operationManager.securityPolicy.allowInvalidCertificates = YES;
        NSString *certPath = [[NSBundle mainBundle] pathForResource:@"whisperReal" ofType:@"cer"];
        NSData *certData = [NSData dataWithContentsOfFile:certPath];
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)(certData));
        self.operationManager.securityPolicy.pinnedCertificates = @[(__bridge_transfer NSData *)SecCertificateCopyData(cert)];
        self.operationManager.securityPolicy.SSLPinningMode     = AFSSLPinningModePublicKey;
    }
    return self;
}

-(TOCFuture*)asyncRequestPushNotificationToDevice:(NSData*)deviceToken {
    self.operationManager.requestSerializer = [self basicAuthenticationSerializer];
    
    TOCFutureSource* result = [TOCFutureSource new];
    [self.operationManager PUT:[NSString stringWithFormat:@"/apn/%@", deviceToken.encodedAsHexString]
                    parameters:@{}
                       success:^(NSURLSessionDataTask *task, id responseObject) { [result trySetResult:task.response]; }
                       failure:^(NSURLSessionDataTask *task, NSError *error) { [result trySetFailure:error]; }];
    return result.future;
}

- (AFHTTPRequestSerializer*)basicAuthenticationSerializer{
    AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
    [serializer setValue:[HttpRequest computeBasicAuthorizationTokenForLocalNumber:[SGNKeychainUtil localNumber]andPassword:[SGNKeychainUtil serverAuthPassword]] forHTTPHeaderField:@"Authorization"];
    return serializer;
}

@end
