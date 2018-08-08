//
//  FLDeviceRegistrationService.m
//  Forsta
//
//  Created by Mark Descalzo on 1/31/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

#import "FLDeviceRegistrationService.h"
#import "TSAccountManager.h"
#import "OWSDeviceProvisioner.h"
#import "ECKeyPair+OWSPrivateKey.h"
#import "NSData+Base64.h"
//#import <AxolotlKit/NSData+keyVersionByte.h>
#import "Cryptography.h"
#import "SRWebSocket.h"
#import "CCSMStorage.h"
#import "CCSMCommunication.h"
//#import "SubProtocol.pb.h"
#import "WebSocketResources.pb.h"
#import "OWSProvisioningCipher.h"
#import "OWSProvisioningProtos.pb.h"
#import "NSData+keyVersionByte.h"
//#import <Curve25519Kit/Curve25519.h>
//#import "Curve25519+keyPairFromPrivateKey.h"
//#import "SignalKeyingStorage.h"
#import "SecurityUtils.h"
#import "TSPreKeyManager.h"
#import "OWSDevice.h"

@import AxolotlKit;
@import SocketRocket;
@import Curve25519Kit;
@import RelayServiceKit;

NSString *const FLRegistrationStatusUpdateNotification = @"FLRegistrationStatusUpdateNotification";

@interface FLDeviceRegistrationService() <SRWebSocketDelegate>

@property (nonatomic, strong) SRWebSocket *provisioningSocket;
@property (readonly) OWSProvisioningCipher *cipher;
@property dispatch_semaphore_t provisioningSemaphore;

@end

@implementation FLDeviceRegistrationService

+ (instancetype)sharedInstance {
    static FLDeviceRegistrationService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

-(instancetype)init
{
    if (self = [super init]) {
        _cipher = [[OWSProvisioningCipher alloc] init];
        _provisioningSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

-(void)registerWithTSSWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completionBlock
{
    [CCSMCommManager checkAccountRegistrationWithCompletion:^(NSDictionary *payload, NSError *checkError) {
        if (checkError == nil) {
            NSString *serverURL = [payload objectForKey:@"serverUrl"];
            // TODO: Store serverURLWSSignal]
            NSArray *devices = [payload objectForKey:@"devices"];
            DDLogInfo(@"Provisioning found %d other registered devices.", (int)devices.count);

            // Found some, request provisioning
            if (devices.count > 0) {
                [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                    object:@{ @"message": @"Other registered devices found." }];
                [self provisionThisDeviceWithCompletion:^(NSError *deviceError) {
                        completionBlock(deviceError);
                }];
            } else { // no other devices, register the account
                [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                    object:@{ @"message": @"Registering account..." }];
                [self registerAcountWithCompletion:^(NSError * _Nullable registerError) {
                    completionBlock(registerError);
                }];
            }
        }
    }];
}

-(void)forceRegistrationWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completionBlock
{
    DDLogDebug(@"Forced device registration initiated.");
    [self registerAcountWithCompletion:^(NSError * _Nullable err) {
        completionBlock(err);
    }];
}

-(void)registerAcountWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completionBlock
{
    NSData *signalingKeyToken = [SecurityUtils generateRandomBytes:(32 + 20)];
    __block NSString *signalingKey = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    
    NSNumber *registrationId = [NSNumber numberWithUnsignedInteger:[TSAccountManager getOrGenerateRegistrationId]];
    
    NSString *name = [NSString stringWithFormat:@"%@ (%@)", [UIDevice currentDevice].localizedModel, [[UIDevice currentDevice] name]];
    __block NSString *authToken = [[SecurityUtils generateRandomBytes:16] base64EncodedString];
    
    NSDictionary *jsonBody = @{ @"signalingKey": signalingKey,
                                @"supportSms" : @NO,
                                @"fetchesMessages" : @YES,
                                @"registrationId" : registrationId,
                                @"name" : name,
                                @"password" : authToken
                                };

    NSDictionary *parameters = @{ @"jsonBody" : jsonBody };
    
    [CCSMCommManager registerAccountWithParameters:parameters
                                        completion:^(NSDictionary *result, NSError *regerror) {
                                            if (regerror != nil) {
                                                completionBlock(regerror);
                                            } else {
                                                NSNumber *deviceID = [result objectForKey:@"deviceId"];
                                                [OWSDeviceManager.sharedManager setCurrentDeviceId:[deviceID unsignedIntValue]];
                                                [TSAccountManager.sharedInstance storeServerAuthToken:authToken signalingKey:signalingKey];
                                                
                                                [TSPreKeyManager registerPreKeysWithMode:RefreshPreKeysMode_SignedAndOneTime success:^{
                                                    completionBlock(nil);
                                                } failure:^(NSError *error) {
                                                    completionBlock(error);
                                                }];
                                            }
                                        }];
}

-(void)provisionThisDeviceWithCompletion:(void (^)(NSError *error))completionBlock
{
    // Open the socket...
    [self.provisioningSocket open];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // Wait 15 seconds then close the socket and call completion.
        dispatch_time_t waittime = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 15);
       long result = dispatch_semaphore_wait(self.provisioningSemaphore, waittime);
        
        [self.provisioningSocket close];
        if (result == 0) {  // Another device provisioned us!  We're good to go.
            [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                object:@{ @"message": @"Device successfully provisioned!" }];
            completionBlock(nil);
        } else {
            // Device provisioning timed-out.
            [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                object:@{ @"message": @"Device provisioning timed-out." }];
            NSError *timeoutError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                        code:NSUserActivityRemoteApplicationTimedOutError
                                                    userInfo:@{ NSLocalizedDescriptionKey : @"No other devices responded to your provisioning request." }];
                completionBlock(timeoutError);
        }
    });
}

-(void)provisionOtherDeviceWithPublicKey:(NSString *_Nonnull)keyString andUUID:(NSString *_Nonnull)uuidString
{
//    NSData *theirPublicKey = [[NSData dataFromBase64String:keyString] removeKeyType];
//    NSString *accountIdentifier = TSAccountManager.sharedInstance.localUID;
//    __block NSData *myPublicKey = nil;
//    __block NSData *myPrivateKey = nil;
//
//    ECKeyPair *myKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];
//    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myKeyPair.publicKey
//                                                                             myPrivateKey:myKeyPair.ows_privateKey
//                                                                           theirPublicKey:theirPublicKey
//                                                                   theirEphemeralDeviceId:uuidString
//                                                                        accountIdentifier:<#(nonnull NSString *)#>
//                                                                               profileKey:<#(nonnull NSData *)#>
//                                                                      readReceiptsEnabled:<#(BOOL)#>
//                                                                  provisioningCodeService:<#(nonnull OWSDeviceProvisioningCodeService *)#>
//                                                                      provisioningService:<#(nonnull OWSDeviceProvisioningService *)#>];
    
//    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myKeyPair.publicKey
//                                                                             myPrivateKey:myKeyPair.ows_privateKey
//                                                                           theirPublicKey:theirPublicKey
//                                                                   theirEphemeralDeviceId:uuidString
//                                                                        accountIdentifier:accountIdentifier];
//    [provisioner provisionWithSuccess:^{
//        DDLogInfo(@"Successfully provisioned other device.");
//        // TODO: Notification UI here perhaps?
////        dispatch_async(dispatch_get_main_queue(), ^{
////        });
//    }
//                              failure:^(NSError *error) {
//                                  DDLogError(@"Failed to provision other device with error: %@", error);
////                                  dispatch_async(dispatch_get_main_queue(), ^{
////                                  });
//                              }];
}

-(void)processProvisioningMessage:(OWSProvisioningProtosProvisionMessage *)messageProto
                   withCompletion:(void (^)(NSError *error))completionBlock
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                        object:@{ @"message": @"Provisioning device." }];
    NSString *accountIdentifier = TSAccountManager.sharedInstance.localUID;
    
    // Validate other device is valid
    if (![accountIdentifier isEqualToString:messageProto.number]) {
        DDLogError(@"Security Violation: Foreign account sent us an identity key!");
        // TODO: throw error or exception here.
        return;
    }
    
    // PUT the things to TSS
    NSString *name = [NSString stringWithFormat:@"%@ (%@)", [[UIDevice currentDevice] localizedModel], [[UIDevice currentDevice] name]];
    [OWSIdentityManager.sharedManager generateKeyPairWithPrivateKey:messageProto.identityKeyPrivate];
    __block ECKeyPair *keyPair = [OWSIdentityManager.sharedManager identityKeyPair];
    NSNumber *registrationId = [NSNumber numberWithUnsignedInteger:[TSAccountManager getOrGenerateRegistrationId]];
    __block NSString *authToken = [[SecurityUtils generateRandomBytes:16] base64EncodedString];
    __block NSData *signalingKeyToken = [SecurityUtils generateRandomBytes:(32 + 20)];
    __block NSString *signalingKey = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    NSString *urlParms = [NSString stringWithFormat:@"/%@", messageProto.provisioningCode];
    
    NSDictionary *payload = @{ @"signalingKey": signalingKey,
                               @"supportSms" : @NO,
                               @"fetchesMessages" : @YES,
                               @"registrationId" : registrationId,
                               @"name" : name,
                               @"password" : authToken
                               };
    NSDictionary *parameters = @{ @"httpType" : @"PUT",
                                  @"urlParms" :  urlParms,
                                  @"jsonBody" : payload,
                                  @"username" : messageProto.number,
                                  @"password" : authToken,
                                  };
    [CCSMCommManager registerDeviceWithParameters:parameters
                                       completion:^(NSDictionary *response, NSError *regerror) {
                                            if (!regerror) {
                                               DDLogDebug(@"Device provision PUT response: %@", response);
                                               NSNumber *deviceId = [response objectForKey:@"deviceId"];
                                           if (deviceId) {
                                                   [OWSDeviceManager.sharedManager setCurrentDeviceId:[deviceId unsignedIntValue]];
                                                   [TSAccountManager.sharedInstance storeServerAuthToken:authToken signalingKey:signalingKey];
                                                   
                                                   [TSPreKeyManager registerPreKeysWithMode:RefreshPreKeysMode_SignedAndOneTime success:^{
                                                       completionBlock(nil);
                                                   } failure:^(NSError *error) {
                                                       completionBlock(error);
                                                   }];
                                               } else {
                                                   DDLogError(@"No device provided by TSS!");
                                                   // FIX: throw meaningful error here.
                                                   NSError *err = [NSError new];
                                                   completionBlock(err);
                                               }
                                           } else {
                                               Logger.error(@"Device provison PUT failed with error: %@", error.description);
                                               completionBlock(regerror);
                                           }
                                       }];
}

// MARK: - Helpers
-(NSURL *)provisioningURL
{
    NSString *tssURLString = [[[CCSMStorage alloc] init] textSecureURL];
    NSString *socketString = [tssURLString stringByReplacingOccurrencesOfString:@"http"
                                                                     withString:@"ws"];
    NSString *urlString = [socketString stringByAppendingString:@"/v1/websocket/provisioning/"];
    NSURL *url = [NSURL URLWithString:urlString];
    
    return url;
}


- (void)sendWebSocketMessageAcknowledgement:(WebSocketRequestMessage *)request
{
    WebSocketResponseMessageBuilder *response = [WebSocketResponseMessage builder];
    [response setStatus:200];
    [response setMessage:@"OK"];
    [response setId:request.id];
    
    WebSocketMessageBuilder *message = [WebSocketMessage builder];
    [message setResponse:response.build];
    [message setType:WebSocketMessageTypeResponse];
    
    NSError *error;
    [self.provisioningSocket sendDataNoCopy:message.build.data error:&error];
    if (error) {
        Looger.warn(@"Error while trying to write on websocket %@", error);
    }
}

// MARK: - SocketRocket delegate methods
- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    DDLogInfo(@"Provisioning socket opened.");
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string
{
    DDLogInfo(@"Provisioning socket received string message: %@", string);
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data
{
    DDLogInfo(@"Provisioning socket received data message.");
    
    WebSocketMessage *message = [WebSocketMessage parseFromData:data];
    
    NSData *ourPublicKeyData = [self.cipher.ourPublicKey prependKeyType];
    NSString *ourPublicKeyString  = [ourPublicKeyData base64EncodedString];
    
    if (message.hasRequest) {
        WebSocketRequestMessage *request = message.request;
        
        if ([request.path isEqualToString:@"/v1/address"] && [request.verb isEqualToString:@"PUT"]) {
            OWSProvisioningProtosProvisioningUuid *proto = [OWSProvisioningProtosProvisioningUuid parseFromData:request.body];
            [self sendWebSocketMessageAcknowledgement:request];
            [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                object:@{ @"message": @"Requesting device provisioning.  Awaiting response..." }];
            NSDictionary *payload = @{ @"uuid" : proto.uuid,
                                       @"key" : ourPublicKeyString };
            
            [CCSMCommManager sendDeviceProvisioningRequestWithPayload:payload];
        } else if ([request.path isEqualToString:@"/v1/message"] && [request.verb isEqualToString:@"PUT"]) {
            OWSProvisioningProtosProvisionEnvelope *proto = [OWSProvisioningProtosProvisionEnvelope parseFromData:request.body];
            [self sendWebSocketMessageAcknowledgement:request];
            [self.provisioningSocket close];
            [[NSNotificationCenter defaultCenter] postNotificationName:FLRegistrationStatusUpdateNotification
                                                                object:@{ @"message": @"Provisioning response received." }];
            // Decrypt the things
            NSData *decryptedData = [self.cipher decrypt:proto];
            OWSProvisioningProtosProvisionMessage *messageProto = [OWSProvisioningProtosProvisionMessage parseFromData:decryptedData];
            [self processProvisioningMessage:messageProto withCompletion:^(NSError *error) {
                dispatch_semaphore_signal(self.provisioningSemaphore);
            }];
            
        } else {
            Logger.info(@"Unhandled provisioning socket request message.");
        }
    }
    
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    DDLogInfo(@"Provisioning socket failed with Error: %@", error.description);
    self.provisioningSocket = nil;
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean
{
    DDLogInfo(@"Provisioning socket closed. Reason: %@", reason);
    self.provisioningSocket = nil;
}

// MARK: - Accessors
-(SRWebSocket *)provisioningSocket
{
    if (_provisioningSocket == nil || _provisioningSocket.url == nil) {
        _provisioningSocket = [[SRWebSocket alloc]initWithURL:[self provisioningURL]];
        _provisioningSocket.delegate = self;
    }
    return _provisioningSocket;
}

@end
