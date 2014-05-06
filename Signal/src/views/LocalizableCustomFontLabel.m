#import "LocalizableCustomFontLabel.h"

@implementation LocalizableCustomFontLabel

- (void)awakeFromNib {
    [super awakeFromNib];
    
    NSString *fontName = [self fontName];
    self.font = [UIFont fontWithName:fontName size:self.font.pointSize];
}

- (void)setLocalizationKey:(NSString *)localizationKey {
    _localizationKey = localizationKey;
    if (_localizationKey) {
        self.text = NSLocalizedString(_localizationKey, @"");
    }
}

- (NSString *)fontName {
    return nil;
}

@end

#define LocalizableCustomFontLabel(CLASS_NAME, FONT_NAME) \
@implementation CLASS_NAME \
- (NSString *)fontName { \
return @"" # FONT_NAME; \
} \
@end \

CUSTOM_FONT_LABELS

#undef LocalizableCustomFontLabel
