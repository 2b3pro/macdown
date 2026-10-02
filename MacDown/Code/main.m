//
//  main.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>

static NSString * const kMPDidMigrateLegacyPreferencesKey =
    @"MPDidMigrateLegacyPreferences";

// This fork ships under its own bundle identifier (com.2b3pro.macdown), so
// macOS keeps its settings in a new preferences domain. On first launch, copy
// the settings saved under upstream MacDown's identifier, keeping anything
// already set in the new domain. Runs once, before anything reads defaults,
// and leaves the old domain untouched.
static void MPMigrateLegacyPreferences(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kMPDidMigrateLegacyPreferencesKey])
        return;

    NSString *domain = [NSBundle mainBundle].bundleIdentifier;
#ifdef DEBUG
    NSArray *legacyDomains =
        @[@"com.uranusjr.macdown-debug", @"com.uranusjr.macdown"];
#else
    NSArray *legacyDomains = @[@"com.uranusjr.macdown"];
#endif
    for (NSString *legacyDomain in legacyDomains)
    {
        NSDictionary *legacy = [defaults persistentDomainForName:legacyDomain];
        if (!legacy.count)
            continue;

        NSMutableDictionary *merged = [legacy mutableCopy];
        NSDictionary *current = [defaults persistentDomainForName:domain];
        if (current)
            [merged addEntriesFromDictionary:current];
        [defaults setPersistentDomain:merged forName:domain];
        break;
    }
    [defaults setBool:YES forKey:kMPDidMigrateLegacyPreferencesKey];
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        MPMigrateLegacyPreferences();
    }
    return NSApplicationMain(argc, argv);
}
