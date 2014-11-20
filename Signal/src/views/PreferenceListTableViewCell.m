#import "PreferenceListTableViewCell.h"

@implementation PreferenceListTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

@end
