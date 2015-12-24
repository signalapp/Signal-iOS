#import <TextSecureKit/TSStorageManager+keyingMaterial.h>
#import <XCTest/XCTest.h>
#import "HttpSocket.h"
#import "SignalKeyingStorage.h"
#import "SignalUtil.h"
#import "TestUtil.h"

@interface SignalKeyingStorage ()
+ (void)storeString:(NSString *)string forKey:(NSString *)key;
@end

@interface HttpRequestResponseTest : XCTestCase

@end

@implementation HttpRequestResponseTest

- (void)setUp {
    [Environment setCurrent:testEnv];
}

- (void)testRequestToInitiate {
    [SignalKeyingStorage storeString:@"shall_not_password" forKey:SAVED_PASSWORD_KEY];
    [SignalKeyingStorage storeString:[@2356 stringValue] forKey:PASSWORD_COUNTER_KEY];
    [TSStorageManager storePhoneNumber:@"+19027778888"];

    HttpRequest *h =
        [HttpRequest httpRequestToInitiateToRemoteNumber:[PhoneNumber phoneNumberFromE164:@"+19023334444"]];
    test([[h method] isEqualToString:@"GET"]);
    test([[h location] isEqualToString:@"/session/1/+19023334444"]);
    test([[SignalKeyingStorage serverAuthPassword] isEqualToString:@"shall_not_password"]);
    NSLog(@"HTTP rep: %@", [self processStrings:h.toHttp]);
    test([h.toHttp isEqualToString:@"GET /session/1/+19023334444 HTTP/1.0\r\nAuthorization: OTP "
                                   @"KzE5MDI3Nzc4ODg4OmluQ3lLcE1ZaFRQS0ZwN3BITlN3bUxVMVpCTT06MjM1Nw==\r\n\r\n"]);
    test([h isEqualToHttpRequest:[HttpRequest httpRequestFromData:[h serialize]]]);
}
- (void)testRequestToOpenPort {
    HttpRequest *h = [HttpRequest httpRequestToOpenPortWithSessionId:2357];
    test([[h method] isEqualToString:@"GET"]);
    test([[h location] isEqualToString:@"/open/2357"]);
    test([h.toHttp isEqualToString:@"GET /open/2357 HTTP/1.0\r\n\r\n"]);
    test([h isEqualToHttpRequest:[HttpRequest httpRequestFromData:[h serialize]]]);
}

- (NSString *)processStrings:(NSString *)something {
    return [[[something stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]
        stringByReplacingOccurrencesOfString:@"\t"
                                  withString:@"\\t"] stringByReplacingOccurrencesOfString:@"\r"
                                                                               withString:@"\\r"];
}

- (void)testRequestToRing {
    [Environment setCurrent:testEnv];
    [TSStorageManager storePhoneNumber:@"+19025555555"];
    [SignalKeyingStorage storeString:@"shall_not_password" forKey:SAVED_PASSWORD_KEY];
    [SignalKeyingStorage storeString:@"-1" forKey:PASSWORD_COUNTER_KEY];
    HttpRequest *h = [HttpRequest httpRequestToRingWithSessionId:458847238];
    test([[h method] isEqualToString:@"RING"]);
    test([[h location] isEqualToString:@"/session/458847238"]);
    test([h.toHttp isEqualToString:@"RING /session/458847238 HTTP/1.0\r\nAuthorization: OTP "
                                   @"KzE5MDI1NTU1NTU1OnpOV1owY3k3S3A5S3NNd0RXbnlHZFBNR2ZzTT06MA==\r\n\r\n"]);
    test([h isEqualToHttpRequest:[HttpRequest httpRequestFromData:[h serialize]]]);
}

- (void)testRequestFromData {
    HttpRequest *h0 =
        [HttpRequest httpRequestFromData:[@"GET /index.html HTTP/1.0\r\nContent-Length: 0\r\n\r\n" encodedAsUtf8]];
    test([[h0 method] isEqualToString:@"GET"]);
    test([[h0 location] isEqualToString:@"/index.html"]);
    test([[h0 headers] count] == 1);
    test([[h0 headers][@"Content-Length"] isEqualToString:@"0"]);
    test([[h0 optionalBody] isEqualToString:@""]);

    HttpRequest *h1 = [HttpRequest
        httpRequestFromData:[@"GET /index.html HTTP/1.0\r\nContent-Length: 10\r\n\r\nabcdefghij" encodedAsUtf8]];
    test([[h1 method] isEqualToString:@"GET"]);
    test([[h1 location] isEqualToString:@"/index.html"]);
    test([[h1 headers] count] == 1);
    test([[h1 headers][@"Content-Length"] isEqualToString:@"10"]);
    test([[h1 optionalBody] isEqualToString:@"abcdefghij"]);

    HttpRequest *h = [HttpRequest httpRequestFromData:@"GET /index.html HTTP/1.0\r\n\r\n".encodedAsUtf8];
    test([[h method] isEqualToString:@"GET"]);
    test([[h location] isEqualToString:@"/index.html"]);
    test([[h headers] count] == 0);
    test([h optionalBody] == nil);

    testThrows([HttpRequest httpRequestFromData:@"GET /index.html HTTP/1.0\r\n".encodedAsUtf8]);
    testThrows(
        [HttpRequest httpRequestFromData:[@"GET /index.html HTTP/1.0\r\nContent-Length: 10\r\n\r\n" encodedAsUtf8]]);
    testThrows([HttpRequest httpRequestFromData:@"GET /index.html\r\n\r\n".encodedAsUtf8]);
}
- (void)testResponseOk {
    HttpResponse *h = [HttpResponse httpResponse200Ok];
    test(h.getStatusCode == 200);
    test(h.getOptionalBodyText == nil);
    test([h.getHeaders count] == 0);
}
- (void)testResponseFromData {
    HttpResponse *h = [HttpResponse httpResponseFromData:@"HTTP/1.1 200 OK\r\n\r\n".encodedAsUtf8];
    test(h.isOkResponse);
    test(h.getStatusCode == 200);
    test([h.getStatusText isEqualToString:@"OK"]);
    test(h.getOptionalBodyText == nil);
    test([h.getHeaders count] == 0);

    HttpResponse *h2 = [HttpResponse httpResponseFromData:@"HTTP/1.1 404 Not Found\r\n\r\n".encodedAsUtf8];
    test(!h2.isOkResponse);
    test(h2.getStatusCode == 404);
    test([h2.getStatusText isEqualToString:@"Not Found"]);
    test(h2.getOptionalBodyText == nil);
    test([h2.getHeaders count] == 0);

    testThrows([HttpResponse httpResponseFromData:@"HTTP/1.1 200 OK\r\n".encodedAsUtf8]);
    testThrows([HttpResponse httpResponseFromData:@"HTTP/1.1 200\r\n\r\n".encodedAsUtf8]);
}
- (void)testTryFromPartialData {
    NSUInteger len;
    HttpRequestOrResponse *h;
    h = [HttpRequestOrResponse tryExtractFromPartialData:@"HTTP/1.1 200".encodedAsUtf8 usedLengthOut:&len];
    test(h == nil);
    h = [HttpRequestOrResponse tryExtractFromPartialData:@"HTTP/1.1 200 OK".encodedAsUtf8 usedLengthOut:&len];
    test(h == nil);
    h = [HttpRequestOrResponse tryExtractFromPartialData:@"HTTP/1.1 200 OK\r\n".encodedAsUtf8 usedLengthOut:&len];
    test(h == nil);

    h = [HttpRequestOrResponse tryExtractFromPartialData:@"HTTP/1.1 200 OK\r\n\r\n".encodedAsUtf8 usedLengthOut:&len];
    test(h.isResponse);
    test([[h response] isOkResponse]);
    test(len == 19);

    h = [HttpRequestOrResponse
        tryExtractFromPartialData:[@"HTTP/1.1 200 OK\r\n\r\n*&DY*SWA(TD&(BTNGNSADN" encodedAsUtf8]
                    usedLengthOut:&len];
    test(h.isResponse);
    test([[h response] isOkResponse]);
    test(len == 19);

    h = [HttpRequestOrResponse tryExtractFromPartialData:@"GET /index.html".encodedAsUtf8 usedLengthOut:&len];
    test(h == nil);
    h = [HttpRequestOrResponse tryExtractFromPartialData:@"GET /index.html HTTP/1.0\r\n".encodedAsUtf8
                                           usedLengthOut:&len];
    test(h == nil);

    h = [HttpRequestOrResponse tryExtractFromPartialData:@"GET /index.html HTTP/1.0\r\n\r\n".encodedAsUtf8
                                           usedLengthOut:&len];
    test(h.isRequest);
    test([[[h request] method] isEqualToString:@"GET"]);
    test(len == 28);

    h = [HttpRequestOrResponse
        tryExtractFromPartialData:[@"GET /index.html HTTP/1.0\r\n\r\nU$%#*(NYVYAY*" encodedAsUtf8]
                    usedLengthOut:&len];
    test(h.isRequest);
    test([[[h request] method] isEqualToString:@"GET"]);
    test(len == 28);

    testThrows([HttpRequestOrResponse tryExtractFromPartialData:@"GET\r\n\r\n".encodedAsUtf8 usedLengthOut:&len]);
    testThrows(
        [HttpRequestOrResponse tryExtractFromPartialData:@"HTTP/1.1 200\r\n\r\n".encodedAsUtf8 usedLengthOut:&len]);
}
@end
