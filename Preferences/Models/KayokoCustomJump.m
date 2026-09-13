//
//  KayokoCustomJump.m
//  Kayoko
//

#import "KayokoCustomJump.h"

NSString *const kKayokoCustomJumpDictionaryKeyUUID = @"uuid";
NSString *const kKayokoCustomJumpDictionaryKeyTitle = @"title";
NSString *const kKayokoCustomJumpDictionaryKeyLink = @"link";
NSString *const kKayokoCustomJumpDictionaryKeyIcon = @"icon";
NSString *const kKayokoCustomJumpDefaultIconName = @"link";

@implementation KayokoCustomJump

- (instancetype)initWithUUID:(NSString *)uuid
                        title:(NSString *)title
                         link:(NSString *)link
                         icon:(NSString *)icon {
    self = [super init];
    if (self) {
        _uuid = [([uuid length] > 0 ? uuid : [[NSUUID UUID] UUIDString]) copy];
        _title = [(title ?: @"") copy];
        _link = [(link ?: @"") copy];
        _icon = [([icon length] > 0 ? icon : kKayokoCustomJumpDefaultIconName) copy];
    }
    return self;
}

- (instancetype)initWithUUID:(NSString *)uuid title:(NSString *)title link:(NSString *)link {
    return [self initWithUUID:uuid title:title link:link icon:nil];
}

+ (instancetype)jumpWithTitle:(NSString *)title link:(NSString *)link {
    return [[self alloc] initWithUUID:[[NSUUID UUID] UUIDString] title:title link:link];
}

+ (instancetype)jumpWithDictionary:(NSDictionary<NSString *, id> *)dictionary {
    id uuid = dictionary[kKayokoCustomJumpDictionaryKeyUUID];
    id title = dictionary[kKayokoCustomJumpDictionaryKeyTitle];
    id link = dictionary[kKayokoCustomJumpDictionaryKeyLink];
    id icon = dictionary[kKayokoCustomJumpDictionaryKeyIcon];
    if (![uuid isKindOfClass:[NSString class]] || ![title isKindOfClass:[NSString class]] ||
        ![link isKindOfClass:[NSString class]] || [uuid length] == 0) {
        return nil;
    }

    return [[self alloc] initWithUUID:uuid
                                title:title
                                 link:link
                                 icon:[icon isKindOfClass:[NSString class]] ? icon : nil];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        kKayokoCustomJumpDictionaryKeyUUID : [self uuid] ?: @"",
        kKayokoCustomJumpDictionaryKeyTitle : [self title] ?: @"",
        kKayokoCustomJumpDictionaryKeyLink : [self link] ?: @"",
        kKayokoCustomJumpDictionaryKeyIcon : [self icon] ?: kKayokoCustomJumpDefaultIconName
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithUUID:[self uuid]
                                                     title:[self title]
                                                      link:[self link]
                                                      icon:[self icon]];
}

@end
