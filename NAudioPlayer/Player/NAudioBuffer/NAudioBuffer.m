//
//  NAudioBuffer.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/23.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioBuffer.h"

@interface NAudioBuffer ()
{
@private
    NSMutableArray *_bufferBlockArray;
    UInt32 _bufferedSize;
}
@end

@implementation NAudioBuffer

+ (instancetype)buffer
{
    return [[self alloc] init];
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _bufferBlockArray = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)hasData
{
    return _bufferBlockArray.count > 0;
}

- (UInt32)bufferedSize
{
    return _bufferedSize;
}

- (void)enqueueFromDataArray:(NSArray <NParseAudioData *>*)dataArray
{
    for (NParseAudioData *data in dataArray){
        [self enqueueData:data];
    }
    
    NSLog(@"个数, _bufferBlockArray.count: %ld", _bufferBlockArray.count);
}

- (void)enqueueData:(NParseAudioData *)data
{
    if ([data isKindOfClass:[NParseAudioData class]]){
        [_bufferBlockArray addObject:data];
        _bufferedSize += data.data.length;
    }
}

- (NSData *)dequeueDataWithSize:(UInt32)requestSize
                    packetCount:(UInt32 *)packetCount
                   descriptions:(AudioStreamPacketDescription *_Nullable*_Nonnull)descriptions
{
    
//    NSLog(@"descriptions 01: %@", descriptions);
    
    if (requestSize == 0 && _bufferBlockArray.count == 0){
        return nil;
    }
    
    SInt64 size = requestSize;
    int i = 0;
    for (i = 0; i < _bufferBlockArray.count ; ++i){
        NParseAudioData *block = _bufferBlockArray[i];
        SInt64 dataLength = [block.data length];
        if (size > dataLength){
            size -= dataLength;
        }else{
            if (size < dataLength){
                i--;
            }
            break;
        }
    }
    
    if (i < 0){
        return nil;
    }
    
    UInt32 count = (i >= _bufferBlockArray.count) ? (UInt32)_bufferBlockArray.count : (i + 1);
    *packetCount = count;
    if (count == 0){
        return nil;
    }
    
    if (descriptions != NULL)
    {
        *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * count);
    }
    
//    descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * count);

//    descriptions = *(AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * count);

    NSMutableData *retData = [[NSMutableData alloc] init];
    for (int j = 0; j < count; ++j){
        NParseAudioData *block = _bufferBlockArray[j];
        if (descriptions != NULL){
            AudioStreamPacketDescription desc = block.packetDescription;
            desc.mStartOffset = [retData length];
            (*descriptions)[j] = desc;
        }
        [retData appendData:block.data];
    }
    
//    NSLog(@"descriptions 02: %@", descriptions);

    NSRange removeRange = NSMakeRange(0, count);
    [_bufferBlockArray removeObjectsInRange:removeRange];
    
    _bufferedSize -= retData.length;
    
    return retData;
}

- (void)clean
{
    _bufferedSize = 0;
    [_bufferBlockArray removeAllObjects];
}

#pragma mark -
- (void)dealloc
{
    [_bufferBlockArray removeAllObjects];
}
@end
