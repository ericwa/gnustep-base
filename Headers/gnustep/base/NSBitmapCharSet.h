/* Interface for NSBitmapCharSet for GNUStep
   Copyright (C) 1995 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: 1995

   This file is part of the GNU Objective C Class Library.

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
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */ 

#ifndef __NSBitmapCharSet_h_OBJECTS_INCLUDE
#define __NSBitmapCharSet_h_OBJECTS_INCLUDE

#include <Foundation/NSCharacterSet.h>
#include <Foundation/NSData.h>

#define UNICODE_SIZE	65536
#define BITMAP_SIZE	UNICODE_SIZE/8

#ifndef SETBIT
#define SETBIT(a,i)     ((a) |= 1<<(i))
#define CLRBIT(a,i)     ((a) &= ~(1<<(i)))
#define ISSET(a,i)      ((((a) & (1<<(i)))) > 0) ? YES : NO;
#endif

@interface NSBitmapCharSet : NSCharacterSet
{
    char data[BITMAP_SIZE];
}

- initWithBitmap:(NSData *)bitmap;

@end

@interface NSMutableBitmapCharSet : NSMutableCharacterSet
{
    char data[BITMAP_SIZE];
}

- initWithBitmap:(NSData *)bitmap;

@end

#endif /* __NSBitmapCharSet_h_OBJECTS_INCLUDE */
