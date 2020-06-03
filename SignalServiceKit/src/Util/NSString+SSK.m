//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NSString+SSK.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSString (SSK)

- (nullable NSString *)dominantLanguageWithLegacyLinguisticTagger
{
    @try {
        // This can throw NSException.
        NSLinguisticTagger *tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:@[
            NSLinguisticTagSchemeLanguage,
        ]
                                                                            options:0];
        tagger.string = self;
        return [tagger tagAtIndex:0 scheme:NSLinguisticTagSchemeLanguage tokenRange:nil sentenceRange:nil];
    } @catch (NSException *exception) {
        // If we find a way to reproduce this issue, we might be able to
        // find a better approach.
        OWSFailDebug(@"Exception: %@, name: %@, reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);
        return nil;
    }
}

@end

NS_ASSUME_NONNULL_END
