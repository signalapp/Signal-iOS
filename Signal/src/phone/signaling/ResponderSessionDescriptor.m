#import "ResponderSessionDescriptor.h"

#import "Constraints.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"
#import "InitiateSignal.pb.h"
#import "SGNKeychainUtil.h"

#define MessagePropertyKey @"m"
#define RelayPortKey       @"p"
#define SessionIdKey       @"s"
#define RelayHostKey       @"n"
#define InitiatorNumberKey @"i"

#define VERSION_SIZE        1
#define IV_SIZE             16
#define HMAC_TRUNCATED_SIZE 10

#define EXPECTED_REMOTE_NOTIF_FORMAT_VERSION 0
#define MAX_SUPPORTED_INTEROP_VERSION 1

@interface ResponderSessionDescriptor ()

@property (nonatomic, readwrite) int32_t interopVersion;
@property (nonatomic, readwrite) in_port_t relayUDPSocketPort;
@property (nonatomic, readwrite) int64_t sessionId;
@property (nonatomic, readwrite) NSString* relayServerName;
@property (nonatomic, readwrite) PhoneNumber* initiatorNumber;

@end

@implementation ResponderSessionDescriptor

- (instancetype)initWithInteropVersion:(int32_t)interopVersion
                       andRelayUDPSocketPort:(in_port_t)relayUDPSocketPort
                          andSessionId:(int64_t)sessionId
                    andRelayServerName:(NSString*)relayServerName
                    andInitiatorNumber:(PhoneNumber*)initiatorNumber {
    self = [super init];
	
    if (self) {
        require(relayUDPSocketPort > 0);
        require(relayServerName != nil);
        require(initiatorNumber != nil);
        
        self.interopVersion  = interopVersion;
        self.relayUDPSocketPort    = relayUDPSocketPort;
        self.sessionId       = sessionId;
        self.relayServerName = relayServerName;
        self.initiatorNumber = initiatorNumber;
    }
    
    return self;
}

- (instancetype)initFromEncryptedRemoteNotification:(NSDictionary*)remoteNotif {
    require(remoteNotif != nil);
    
    NSString* message = remoteNotif[MessagePropertyKey];
    checkOperation(message != nil);
    NSData* authenticatedPayload = [message decodedAsBase64Data];
    
    checkOperation(authenticatedPayload.length > 0);
    uint8_t includedRemoteNotificationFormatVersion = [authenticatedPayload uint8At:0];
    checkOperation(includedRemoteNotificationFormatVersion == EXPECTED_REMOTE_NOTIF_FORMAT_VERSION);
    
    NSData* encryptedPayload = [ResponderSessionDescriptor verifyAndRemoveMacFromRemoteNotifcationData:authenticatedPayload];
    NSData* payload = [ResponderSessionDescriptor decryptRemoteNotificationData:encryptedPayload];
    
    InitiateSignal* parsedPayload = [InitiateSignal parseFromData:payload];
    
    in_port_t maxPort = (in_port_t)-1;
    assert(maxPort > 0);
    checkOperation(parsedPayload.version >= 0);
    checkOperation(parsedPayload.version <= MAX_SUPPORTED_INTEROP_VERSION);
    checkOperation(parsedPayload.sessionId >= 0);
    checkOperation(parsedPayload.port > 0 && parsedPayload.port <= maxPort);
    checkOperation(parsedPayload.initiator != nil);
    checkOperation(parsedPayload.serverName != nil);
    
    int32_t interopVersion = parsedPayload.version;
    int64_t sessionId = parsedPayload.sessionId;
    in_port_t relayUDPSocketPort = (in_port_t)parsedPayload.port;
    NSString* relayServerName = parsedPayload.serverName;
    PhoneNumber* phoneNumber = [[PhoneNumber alloc] initFromE164:parsedPayload.initiator];
    
    return [self initWithInteropVersion:interopVersion
                        andRelayUDPSocketPort:relayUDPSocketPort
                           andSessionId:sessionId
                     andRelayServerName:relayServerName
                     andInitiatorNumber:phoneNumber];
}

+ (NSData*)verifyAndRemoveMacFromRemoteNotifcationData:(NSData*)data {
    require(data != nil);
    checkOperation(data.length >= HMAC_TRUNCATED_SIZE);
    NSData* includedMac     = [data takeLast:HMAC_TRUNCATED_SIZE];
    NSData* payload         = [data skipLast:HMAC_TRUNCATED_SIZE];
    NSData* signalingMacKey = [SGNKeychainUtil signalingMacKey];
    require(signalingMacKey != nil);
    NSData* computedMac     = [[payload hmacWithSHA1WithKey:signalingMacKey] takeLast:HMAC_TRUNCATED_SIZE];
    checkOperation([includedMac isEqualToData_TimingSafe:computedMac]);
    return payload;
}

+ (NSData*)decryptRemoteNotificationData:(NSData*)data {
    require(data != nil);
    checkOperation(data.length >= VERSION_SIZE + IV_SIZE);
    NSData* cipherKey = [SGNKeychainUtil signalingCipherKey];
    require(cipherKey != nil);
    NSData* iv = [data subdataWithRange:NSMakeRange(VERSION_SIZE, IV_SIZE)];
    NSData* cipherText = [data skip:VERSION_SIZE+IV_SIZE];
    return [cipherText decryptWithAESInCipherBlockChainingModeWithPkcs7PaddingWithKey:cipherKey andIV:iv];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"relay name: %@, relay port: %d, session id: %llud, interop version: %d",
            self.relayServerName,
            self.relayUDPSocketPort,
            self.sessionId,
            self.interopVersion];
}

@end
