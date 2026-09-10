//
//  KayokoQuickAction.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, KayokoQuickActionKind) {
    KayokoQuickActionKindText,
    KayokoQuickActionKindImage,
};

@interface KayokoQuickAction : NSObject

+ (NSArray<NSDictionary<NSString *, id> *> *)actionsForKind:(KayokoQuickActionKind)kind;
+ (nullable NSURL *)URLForAction:(NSDictionary<NSString *, id> *)action input:(nullable NSString *)input;

@end

NS_ASSUME_NONNULL_END
