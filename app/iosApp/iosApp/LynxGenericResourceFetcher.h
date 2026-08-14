// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Implemented for the Lynx template project to load runtime-requested Lynx
// resources such as rspeedy HMR patches outside the template provider flow.

#import <Lynx/LynxGenericResourceFetcher.h>

NS_ASSUME_NONNULL_BEGIN

/// App-owned generic resource fetcher for runtime-loaded Lynx resources.
@interface AppGenericResourceFetcher : NSObject <LynxGenericResourceFetcher>
@end

NS_ASSUME_NONNULL_END
