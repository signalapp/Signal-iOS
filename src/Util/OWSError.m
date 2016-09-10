//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSignalServiceKitErrorDomain = @"OWSSignalServiceKitErrorDomain";

NSError *OWSErrorWithCodeDescription(OWSErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:OWSSignalServiceKitErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

NS_ASSUME_NONNULL_END
