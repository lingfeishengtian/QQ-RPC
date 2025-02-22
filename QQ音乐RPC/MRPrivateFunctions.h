//
//  MRPrivateFunctions.h
//  QQ音乐RPC
//
//  Created by Hunter Han on 2/21/25.
//

#ifndef MRPrivateFunctions_h
#define MRPrivateFunctions_h

#include <PrivateProtocolBuffer/PrivateProtocolBuffer.h>

typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion)(int PID);
void MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion completion);

#endif /* MRPrivateFunctions_h */
