//
//  ViewController.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "ViewController.h"
#import "NAudioPlayer.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *playBtn;

@property (weak, nonatomic) IBOutlet UIButton *stopBtn;

@property (weak, nonatomic) IBOutlet UISlider *progressSlider;

@property (nonatomic, strong) NAudioPlayer *player;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"MP3Sample" ofType:@"mp3"];
    
    _player = [[NAudioPlayer alloc] initWithFilePath:path];
}

- (IBAction)handlePlay:(UIButton *)sender
{
    NSLog(@"开始、暂停");
    [_player play];
}

- (IBAction)handleStop:(UIButton *)sender
{
    NSLog(@"停止");
}

- (IBAction)handleProgressSlider:(UISlider *)sender
{
    NSLog(@"进度条");
}

@end
