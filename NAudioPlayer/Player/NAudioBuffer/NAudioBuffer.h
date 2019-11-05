//
//  NAudioBuffer.h
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/23.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "NParseAudioData.h"

NS_ASSUME_NONNULL_BEGIN

@interface NAudioBuffer : NSObject

+ (instancetype)buffer;

- (void)enqueueData:(NParseAudioData *)data;

- (void)enqueueFromDataArray:(NSArray <NParseAudioData *>*)dataArray;

- (BOOL)hasData;

- (UInt32)bufferedSize;

//descriptions needs free
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription *_Nullable*_Nonnull)descriptions;

- (void)clean;


@end

NS_ASSUME_NONNULL_END
