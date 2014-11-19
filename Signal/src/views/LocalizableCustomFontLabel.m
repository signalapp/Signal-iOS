#import "LocalizableCustomFontLabel.h"

@implementation LocalizableCustomFontLabel

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.font = [UIFont fontWithName:[self fontName] size:self.font.pointSize];
}

- (void)setLocalizationKey:(NSString*)localizationKey {
    self.localizationKey = localizationKey;
    if (self.localizationKey) {
        self.text = NSLocalizedString(self.localizationKey, @"");
    }
}

- (NSString*)fontName {
    return nil;
}

@end

#define LocalizableCustomFontLabel(CLASS_NAME, FONT_NAME) \
@implementation CLASS_NAME \
- (NSString*)fontName { \
return @"" # FONT_NAME; \
} \
@end \

CUSTOM_FONT_LABELS

#undef LocalizableCustomFontLabel
