/* Test Class for NSBundle.
   Copyright (C) 1993,1994,1995 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: Jul 1995

   This file is part of the GNUstep Base Library.

*/
#include <stdio.h>
#include <Foundation/NSString.h>
#include "LoadMe.h"

@implementation LoadMe

- init
{
    [super init];
    var = 10;
    return self;
}

- afterLoad
{
    printf("%s's instance variable is %i\n", [[self description] cString], var);
    return self;
}

@end
