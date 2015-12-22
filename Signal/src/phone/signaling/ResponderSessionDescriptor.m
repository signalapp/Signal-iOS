#import "ResponderSessionDescriptor.h"

#import "Constraints.h"
#import "CryptoTools.h"
#import "InitiateSignal.pb.h"
#import "SignalKeyingStorage.h"
#import "Util.h"

#define MessagePropertyKey @"m"
#define RelayPortKey @"p"
#define SessionIdKey @"s"
#define RelayHostKey @"n"
#define InitiatorNumberKey @"i"

#define VERSION_SIZE 1
#define IV_SIZE 16
#define HMAC_TRUNCATED_SIZE 10

#define EXPECTED_REMOTE_NOTIF_FORMAT_VERSION 0
#define MAX_SUPPORTED_INTEROP_VERSION 1

@implementation ResponderSessionDescriptor

@synthesize relayUdpPort;
@synthesize sessionId;
@synthesize relayServerName;
@synthesize initiatorNumber;
@synthesize interopVersion;

+ (ResponderSessionDescriptor *)responderSessionDescriptorWithInteropVersion:(NSUInteger)interopVersion
                                                             andRelayUdpPort:(in_port_t)relayUdpPort
                                                                andSessionId:(int64_t)sessionId
                                                          andRelayServerName:(NSString *)relayServerName
                                                          andInitiatorNumber:(PhoneNumber *)initiatorNumber {
    ows_require(relayUdpPort > 0);
    ows_require(relayServerName != nil);
    ows_require(initiatorNumber != nil);

    ResponderSessionDescriptor *rsd = [ResponderSessionDescriptor new];
    rsd->interopVersion             = interopVersion;
    rsd->relayUdpPort               = relayUdpPort;
    rsd->sessionId                  = sessionId;
    rsd->relayServerName            = relayServerName;
    rsd->initiatorNumber            = initiatorNumber;

    return rsd;
}

+ (ResponderSessionDescriptor *)responderSessionDescriptorFromEncryptedRemoteNotification:(NSDictionary *)remoteNotif {
    ows_require(remoteNotif != nil);

    NSString *message = remoteNotif[MessagePropertyKey];
    checkOperation(message != nil);
    NSData *authenticatedPayload = [message decodedAsBase64Data];

    checkOperation(authenticatedPayload.length > 0);
    uint8_t includedRemoteNotificationFormatVersion = [authenticatedPayload uint8At:0];
    checkOperation(includedRemoteNotificationFormatVersion == EXPECTED_REMOTE_NOTIF_FORMAT_VERSION);

    NSData *encryptedPayload = [self verifyAndRemoveMacFromRemoteNotifcationData:authenticatedPayload];
    NSData *payload          = [self decryptRemoteNotificationData:encryptedPayload];

    InitiateSignal *parsedPayload = [InitiateSignal parseFromData:payload];

    in_port_t maxPort = (in_port_t)-1;
    assert(maxPort > 0);
    checkOperation(parsedPayload.version >= 0);
    checkOperation(parsedPayload.version <= MAX_SUPPORTED_INTEROP_VERSION);
    checkOperation(parsedPayload.sessionId >= 0);
    checkOperation(parsedPayload.port > 0 && parsedPayload.port <= maxPort);
    checkOperation(parsedPayload.initiator != nil);
    checkOperation(parsedPayload.serverName != nil);

    NSUInteger interopVersion = parsedPayload.version;
    int64_t sessionId         = (int64_t)parsedPayload.sessionId;
    in_port_t relayUdpPort    = (in_port_t)parsedPayload.port;
    NSString *relayServerName = parsedPayload.serverName;
    PhoneNumber *phoneNumber  = [PhoneNumber phoneNumberFromE164:parsedPayload.initiator];

    return [ResponderSessionDescriptor responderSessionDescriptorWithInteropVersion:interopVersion
                                                                    andRelayUdpPort:relayUdpPort
                                                                       andSessionId:sessionId
                                                                 andRelayServerName:relayServerName
                                                                 andInitiatorNumber:phoneNumber];
}
+ (NSData *)verifyAndRemoveMacFromRemoteNotifcationData:(NSData *)data {
    ows_require(data != nil);
    checkOperation(data.length >= HMAC_TRUNCATED_SIZE);
    NSData *includedMac     = [data takeLast:HMAC_TRUNCATED_SIZE];
    NSData *payload         = [data skipLast:HMAC_TRUNCATED_SIZE];
    NSData *signalingMacKey = SignalKeyingStorage.signalingMacKey;
    ows_require(signalingMacKey != nil);
    NSData *computedMac = [[payload hmacWithSha1WithKey:signalingMacKey] takeLast:HMAC_TRUNCATED_SIZE];
    checkOperation([includedMac isEqualToData_TimingSafe:computedMac]);
    return payload;
}
+ (NSData *)decryptRemoteNotificationData:(NSData *)data {
    ows_require(data != nil);
    checkOperation(data.length >= VERSION_SIZE + IV_SIZE);
    NSData *cipherKey = SignalKeyingStorage.signalingCipherKey;
    ows_require(cipherKey != nil);
    NSData *iv         = [data subdataWithRange:NSMakeRange(VERSION_SIZE, IV_SIZE)];
    NSData *cipherText = [data skip:VERSION_SIZE + IV_SIZE];
    return [cipherText decryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:cipherKey andIv:iv];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"relay name: %@, relay port: %d, session id: %llud, interop version: %lu",
                                      relayServerName,
                                      relayUdpPort,
                                      sessionId,
                                      (unsigned long)interopVersion];
}

@end
