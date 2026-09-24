#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CWTextCleaner : NSObject
+ (NSString *)clean:(NSString *)source removeFillers:(BOOL)removeFillers;
@end

NS_ASSUME_NONNULL_END
