/* Interface for holding and dispatching notifications
   Copyright (C) 1996 Free Software Foundation, Inc.

   Written by:  R. Andrew McCallum <mccallum@gnu.ai.mit.edu>
   Created: March 1996

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

#include <objects/stdobjects.h>
#include <objects/NSString.h>
#include <objects/KeyedCollecting.h>
#include <objects/NotificationDispatcher.h>

@interface Notification : NSObject
{
  id _name;
  id _object;
  id _info;
}

+ notificationWithName: (id <String>)name
		object: object;

+ notificationWithName: (id <String>)name
		object: object
	      userInfo: info;

- (id <String>) name;
- object;
- userInfo;

@end
