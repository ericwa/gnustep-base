/* Interface to concrete implementation of NSArchiver
   Copyright (C) 1995, 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: April 1995
   
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

#ifndef __NSGArchiver_h_GNUSTEP_BASE_INCLUDE
#define __NSGArchiver_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSArchiver.h>
#include <base/Coding.h>

@interface NSGArchiver : NSArchiver
@end

@interface NSGArchiver (GNU) <Encoding>
@end

@interface NSGUnarchiver : NSUnarchiver
@end

@interface NSGUnarchiver (GNU) <Decoding>
@end

#endif /* __NSGArchiver_h_GNUSTEP_BASE_INCLUDE */
