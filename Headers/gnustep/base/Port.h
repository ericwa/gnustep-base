/* Interface for abstract superclass port for use with Connection
   Copyright (C) 1994, 1995, 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: July 1994
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
   */ 

#ifndef __Port_h_GNUSTEP_BASE_INCLUDE
#define __Port_h_GNUSTEP_BASE_INCLUDE

#include <base/Coding.h>
#include <base/MemoryStream.h>
#include <Foundation/NSPort.h>
#include <Foundation/NSDate.h>
#include <Foundation/NSString.h>

/* xxx Use something like this? */
@protocol PacketSending
@end

@interface Port : NSPort
{
}
- (void) close;

+ (Class) outPacketClass;
- (Class) outPacketClass;

@end


@interface InPort : Port
{
  id _packet_invocation;
}

+ newForReceiving;
+ newForReceivingFromRegisteredName: (NSString*)name;
+ newForReceivingFromRegisteredName: (NSString*)name fromPort: (int)port;

/* Register/Unregister this port for input handling through RunLoop 
   RUN_LOOP in mode MODE. */
- (void) addToRunLoop: run_loop forMode: (NSString*)mode;
- (void) removeFromRunLoop: run_loop forMode: (NSString*)mode;

/* When a RunLoop is handling this InPort, and a new incoming
   packet arrives, INVOCATION will be invoked with the new packet
   as an argument.  The INVOCATION is responsible for releasing
   the packet. */
- (void) setReceivedPacketInvocation: (id)invocation;

/* An alternative to the above way for receiving packets from this port.
   Get a packet from the net and return it.  If no packet is received 
   within MILLISECONDS, then return nil.  The caller is responsible 
   for releasing the packet. */
- receivePacketWithTimeout: (int)milliseconds;

@end


@interface OutPort : Port

+ newForSendingToRegisteredName: (NSString*)name 
                         onHost: (NSString*)hostname;
- (BOOL) sendPacket: packet timeout: (NSTimeInterval)t;

@end


/* Objects for holding incoming/outgoing data to/from ports. */

@interface InPacket : MemoryStream
{
  id _receiving_in_port;
  id _reply_out_port;
}

- replyOutPort;
- receivingInPort;

/* Do not call this method yourself; it is to be called by subclassers. 
   InPackets are created for you by the InPort object, and are
   made available as the argument to the received packet invocation. */
- initForReceivingWithCapacity: (unsigned)s
               receivingInPort: ip
                  replyOutPort: op;

@end

@interface OutPacket : MemoryStream
{
  id _reply_in_port;
}

- initForSendingWithCapacity: (unsigned)c
   replyInPort: p;
- replyInPort;

+ (unsigned) prefixSize;

@end

#endif /* __Port_h_GNUSTEP_BASE_INCLUDE */
