//
//  MacKeychainShim.m
//  ArcSign Keychain Interposer for Certless MacCatalyst Apps
//
//  Directly intercepts SecItemAdd, SecItemCopyMatching, SecItemUpdate, and SecItemDelete
//  for ad-hoc signed MacCatalyst apps, persisting items in an app-local container plist
//  without triggering macOS securityd -34018 errors or blocking SecurityAgent prompts.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <os/lock.h>

typedef struct interpose_s {
    void *new_func;
    void *orig_func;
} interpose_t;

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static const interpose_t interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (void *)(unsigned long)&_replacement, \
        (void *)(unsigned long)&_replacee \
    };

static os_unfair_lock g_storeLock = OS_UNFAIR_LOCK_INIT;

static NSString *ASKeychainStorePath(void) {
    static NSString *cachedPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *baseDir = paths.firstObject ?: NSTemporaryDirectory();
        NSString *shimDir = [baseDir stringByAppendingPathComponent:@".ArcSignKeychain"];
        [[NSFileManager defaultManager] createDirectoryAtPath:shimDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: [[NSProcessInfo processInfo] processName];
        cachedPath = [shimDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
    });
    return cachedPath;
}

static NSMutableArray<NSMutableDictionary *> *ASLoadItemsLocked(void) {
    NSData *data = [NSData dataWithContentsOfFile:ASKeychainStorePath()];
    if (!data) {
        return [NSMutableArray array];
    }
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:nil
                                                         error:nil];
    if ([obj isKindOfClass:[NSArray class]]) {
        return (NSMutableArray *)obj;
    }
    return [NSMutableArray array];
}

static void ASSaveItemsLocked(NSArray<NSDictionary *> *items) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:items
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:nil];
    if (data) {
        [data writeToFile:ASKeychainStorePath() atomically:YES];
    }
}

static NSArray<NSString *> *ASIdentityKeys(void) {
    return @[
        (__bridge NSString *)kSecClass,
        (__bridge NSString *)kSecAttrService,
        (__bridge NSString *)kSecAttrAccount,
        (__bridge NSString *)kSecAttrGeneric,
        (__bridge NSString *)kSecAttrLabel,
        (__bridge NSString *)kSecAttrServer,
        (__bridge NSString *)kSecAttrSecurityDomain
    ];
}

static NSMutableDictionary *ASSanitizeRecord(NSDictionary *dict) {
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    for (id key in dict) {
        if (![key isKindOfClass:[NSString class]]) continue;
        id val = dict[key];
        if ([val isKindOfClass:[NSString class]] ||
            [val isKindOfClass:[NSData class]] ||
            [val isKindOfClass:[NSNumber class]] ||
            [val isKindOfClass:[NSDate class]]) {
            clean[key] = val;
        }
    }
    if (!clean[(__bridge NSString *)kSecClass]) {
        clean[(__bridge NSString *)kSecClass] = (__bridge NSString *)kSecClassGenericPassword;
    }
    return clean;
}

static BOOL ASRecordMatchesQuery(NSDictionary *record, NSDictionary *query) {
    for (NSString *key in ASIdentityKeys()) {
        id qVal = query[key];
        if (!qVal) continue;
        id rVal = record[key];
        if (!rVal || ![rVal isEqual:qVal]) {
            return NO;
        }
    }
    return YES;
}

static id ASFormatReturnItem(NSDictionary *record, NSDictionary *query) {
    BOOL wantData = [query[(__bridge NSString *)kSecReturnData] boolValue];
    BOOL wantAttrs = [query[(__bridge NSString *)kSecReturnAttributes] boolValue];
    BOOL wantRef = [query[(__bridge NSString *)kSecReturnPersistentRef] boolValue];

    NSData *valueData = record[(__bridge NSString *)kSecValueData];
    if (wantData && !wantAttrs && !wantRef) {
        return valueData ?: [NSData data];
    }
    if (wantAttrs || wantRef) {
        NSMutableDictionary *out = [record mutableCopy];
        if (!wantData) {
            [out removeObjectForKey:(__bridge NSString *)kSecValueData];
        }
        if (wantRef) {
            NSData *refData = [NSPropertyListSerialization dataWithPropertyList:record
                                                                         format:NSPropertyListBinaryFormat_v1_0
                                                                        options:0
                                                                          error:nil];
            if (refData) {
                out[(__bridge NSString *)kSecValuePersistentRef] = refData;
            }
        }
        return out;
    }
    return record;
}

static OSStatus AS_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!attributes) return errSecParam;
    NSDictionary *query = (__bridge NSDictionary *)attributes;

    os_unfair_lock_lock(&g_storeLock);
    NSMutableArray<NSMutableDictionary *> *items = ASLoadItemsLocked();

    for (NSDictionary *existing in items) {
        if (ASRecordMatchesQuery(existing, query)) {
            os_unfair_lock_unlock(&g_storeLock);
            return errSecDuplicateItem;
        }
    }

    NSMutableDictionary *record = ASSanitizeRecord(query);
    record[(__bridge NSString *)kSecAttrCreationDate] = [NSDate date];
    record[(__bridge NSString *)kSecAttrModificationDate] = [NSDate date];
    [items addObject:record];
    ASSaveItemsLocked(items);

    if (result) {
        id formatted = ASFormatReturnItem(record, query);
        *result = CFBridgingRetain(formatted);
    }
    os_unfair_lock_unlock(&g_storeLock);
    return errSecSuccess;
}

static OSStatus AS_SecItemCopyMatching(CFDictionaryRef queryRef, CFTypeRef *result) {
    if (!queryRef) return errSecParam;
    NSDictionary *query = (__bridge NSDictionary *)queryRef;

    os_unfair_lock_lock(&g_storeLock);
    NSMutableArray<NSMutableDictionary *> *items = ASLoadItemsLocked();

    BOOL matchAll = [query[(__bridge NSString *)kSecMatchLimit] isEqual:(__bridge id)kSecMatchLimitAll];
    NSMutableArray *matches = [NSMutableArray array];

    for (NSDictionary *record in items) {
        if (ASRecordMatchesQuery(record, query)) {
            [matches addObject:ASFormatReturnItem(record, query)];
            if (!matchAll) break;
        }
    }
    os_unfair_lock_unlock(&g_storeLock);

    if (matches.count == 0) {
        return errSecItemNotFound;
    }
    if (result) {
        *result = CFBridgingRetain(matchAll ? matches : matches.firstObject);
    }
    return errSecSuccess;
}

static OSStatus AS_SecItemUpdate(CFDictionaryRef queryRef, CFDictionaryRef attributesToUpdateRef) {
    if (!queryRef || !attributesToUpdateRef) return errSecParam;
    NSDictionary *query = (__bridge NSDictionary *)queryRef;
    NSMutableDictionary *updates = ASSanitizeRecord((__bridge NSDictionary *)attributesToUpdateRef);
    [updates removeObjectForKey:(__bridge NSString *)kSecClass];

    os_unfair_lock_lock(&g_storeLock);
    NSMutableArray<NSMutableDictionary *> *items = ASLoadItemsLocked();
    BOOL updated = NO;
    for (NSMutableDictionary *record in items) {
        if (ASRecordMatchesQuery(record, query)) {
            [record addEntriesFromDictionary:updates];
            record[(__bridge NSString *)kSecAttrModificationDate] = [NSDate date];
            updated = YES;
        }
    }
    if (updated) {
        ASSaveItemsLocked(items);
    }
    os_unfair_lock_unlock(&g_storeLock);
    return updated ? errSecSuccess : errSecItemNotFound;
}

static OSStatus AS_SecItemDelete(CFDictionaryRef queryRef) {
    if (!queryRef) return errSecParam;
    NSDictionary *query = (__bridge NSDictionary *)queryRef;

    os_unfair_lock_lock(&g_storeLock);
    NSMutableArray<NSMutableDictionary *> *items = ASLoadItemsLocked();
    NSIndexSet *toRemove = [items indexesOfObjectsPassingTest:^BOOL(NSMutableDictionary *record, NSUInteger idx, BOOL *stop) {
        return ASRecordMatchesQuery(record, query);
    }];
    if (toRemove.count > 0) {
        [items removeObjectsAtIndexes:toRemove];
        ASSaveItemsLocked(items);
        os_unfair_lock_unlock(&g_storeLock);
        return errSecSuccess;
    }
    os_unfair_lock_unlock(&g_storeLock);
    return errSecItemNotFound;
}

DYLD_INTERPOSE(AS_SecItemAdd, SecItemAdd)
DYLD_INTERPOSE(AS_SecItemCopyMatching, SecItemCopyMatching)
DYLD_INTERPOSE(AS_SecItemUpdate, SecItemUpdate)
DYLD_INTERPOSE(AS_SecItemDelete, SecItemDelete)
