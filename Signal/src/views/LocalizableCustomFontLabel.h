#import <UIKit/UIKit.h>

/**
 *
 * This class enables us to set custom fonts for labels in the xib without making an outlet and setting it manually
 * Also contains a property for localization purposes
 *
 */

#define CUSTOM_FONT_LABELS \
LocalizableCustomFontLabel(HelveticaNeueLTStdBoldLabel, HelveticaNeueLTStd-Bold) \
LocalizableCustomFontLabel(HelveticaNeueLTStdLightLabel, HelveticaNeueLTStd-Lt) \
LocalizableCustomFontLabel(HelveticaNeueLTStdMedLabel, HelveticaNeueLTStd-Md) \
LocalizableCustomFontLabel(HelveticaNeueLTStdThinLabel, HelveticaNeueLTStd-Th) \

@interface LocalizableCustomFontLabel : UILabel

@property (strong, nonatomic) NSString* localizationKey;

@end

#define LocalizableCustomFontLabel(CLASS_NAME, FONT_NAME) @interface CLASS_NAME : LocalizableCustomFontLabel {} @end
CUSTOM_FONT_LABELS
#undef LocalizableCustomFontLabel
