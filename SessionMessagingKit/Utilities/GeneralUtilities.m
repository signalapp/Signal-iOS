#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import "GeneralUtilities.h"
#import "OWSIdentityManager.h"

NS_ASSUME_NONNULL_BEGIN

@implementation SNGeneralUtilities

+ (NSString *)getUserPublicKey
{
    return OWSIdentityManager.sharedManager.identityKeyPair.hexEncodedPublicKey;
}

@end

NS_ASSUME_NONNULL_END
