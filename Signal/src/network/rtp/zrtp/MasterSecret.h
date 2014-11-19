#import <Foundation/Foundation.h>
#import "Zid.h"
#import "HelloPacket.h"
#import "CommitPacket.h"
#import "DHPacket.h"

/**
 *
 * MasterSecret is responsible for computing and storing the crypto keys derived by both sides of the zrtp handshake.
 * Both the authenticated portions of the handshake packets and the result of key agreement affect the master secret.
 *
**/

@interface MasterSecret : NSObject

@property (nonatomic, readonly) NSData* totalHash;
@property (nonatomic, readonly) NSData* counter;
@property (nonatomic, readonly) NSData* sharedSecret;
@property (nonatomic, readonly) NSData* shortAuthenticationStringData;

@property (nonatomic, readonly) Zid* responderZid;
@property (nonatomic, readonly) NSData* responderSrtpKey;
@property (nonatomic, readonly) NSData* responderSrtpSalt;
@property (nonatomic, readonly) NSData* responderMacKey;
@property (nonatomic, readonly) NSData* responderZRTPKey;

@property (nonatomic, readonly) Zid* initiatorZid;
@property (nonatomic, readonly) NSData* initiatorSrtpKey;
@property (nonatomic, readonly) NSData* initiatorSrtpSalt;
@property (nonatomic, readonly) NSData* initiatorMacKey;
@property (nonatomic, readonly) NSData* initiatorZRTPKey;

+ (instancetype)masterSecretFromDHResult:(NSData*)dhResult
                       andInitiatorHello:(HelloPacket*)initiatorHello
                       andResponderHello:(HelloPacket*)responderHello
                               andCommit:(CommitPacket*)commit
                              andDhPart1:(DHPacket*)dhPart1
                              andDhPart2:(DHPacket*)dhPart2;

+ (NSData*)calculateSharedSecretFromDhResult:(NSData*)dhResult
                                andTotalHash:(NSData*)totalHash
                             andInitiatorZid:(Zid*)initiatorZid
                             andResponderZid:(Zid*)responderZid;

+ (NSData*)calculateTotalHashFromResponderHello:(HelloPacket*)responderHello
                                      andCommit:(CommitPacket*)commit
                                     andDhPart1:(DHPacket*)dhPart1
                                     andDhPart2:(DHPacket*)dhPart2;

- (instancetype)initFromSharedSecret:(NSData*)sharedSecret
                        andTotalHash:(NSData*)totalHash
                     andInitiatorZid:(Zid*)initiatorZid
                     andResponderZid:(Zid*)responderZid;

- (NSString*)shortAuthenticationString;

@end
