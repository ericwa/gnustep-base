/* Implementation for NSDate for GNUStep
   Copyright (C) 1995, 1996, 1997, 1998 Free Software Foundation, Inc.

   Written by:  Jeremy Bettis <jeremy@hksys.com>
   Rewritten by:  Scott Christley <scottc@net-community.com>
   Date: March 1995
   Modifications by: Richard Frith-Macdonald <richard@brainstorm.co.uk>

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
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */

/*
  1995-03-31 02:41:00 -0600	Jeremy Bettis <jeremy@hksys.com>
  Release the first draft of NSDate.
  Three methods not implemented, and NSCalendarDate/NSTimeZone don't exist.
*/

#include <config.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSDate.h>
#include <Foundation/NSString.h>
#include <Foundation/NSCoder.h>
#include <Foundation/NSException.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSCharacterSet.h>
#include <Foundation/NSScanner.h>
#ifndef __WIN32__
#include <time.h>
#endif /* !__WIN32__ */
#include <stdio.h>
#include <stdlib.h>
#ifndef __WIN32__
#include <sys/time.h>
#endif /* !__WIN32__ */

/* The number of seconds between 1/1/2001 and 1/1/1970 = -978307200. */
/* This number comes from: 
-(((31 years * 365 days) + 8 days for leap years) =total number of days
  * 24 hours
  * 60 minutes
  * 60 seconds)
  This ignores leap-seconds. */
#define UNIX_REFERENCE_INTERVAL -978307200.0

/* I hope 100,000 years is distant enough. */
#define DISTANT_YEARS 100000.0
#define DISTANT_FUTURE	(DISTANT_YEARS * 365.0 * 24 * 60 * 60)
#define DISTANT_PAST	(-DISTANT_FUTURE)

static NSString*
findInArray(NSArray *array, unsigned pos, NSString *str)
{
  unsigned	index;
  unsigned	limit = [array count];

  for (index = pos; index < limit; index++)
    {
      NSString	*item;

      item = [array objectAtIndex: index];
      if ([str caseInsensitiveCompare: item] == NSOrderedSame)
	return item;
    } 
  return nil;
}


/* The implementation of NSDate. */

@implementation NSDate

static BOOL	debug = NO;

// Getting current time

+ (NSTimeInterval) timeIntervalSinceReferenceDate
{
#if !defined(__WIN32__) && !defined(_WIN32)
  volatile NSTimeInterval interval;
  struct timeval tp;

  interval = UNIX_REFERENCE_INTERVAL;
  gettimeofday (&tp, NULL);
  interval += tp.tv_sec;
  interval += (double)tp.tv_usec / 1000000.0;

  /* There seems to be a problem with bad double arithmetic... */
  NSAssert(interval < 0, NSInternalInconsistencyException);

  return interval;
#else
  TIME_ZONE_INFORMATION sys_time_zone;
  SYSTEMTIME sys_time;
  NSCalendarDate *d;
  NSTimeInterval t;

  // Get the time zone information
  GetTimeZoneInformation(&sys_time_zone);

  // Get the system time
  GetLocalTime(&sys_time);

  // Use an NSCalendar object to make it easier
  d = [NSCalendarDate alloc];
  [d initWithYear: sys_time.wYear
     month: sys_time.wMonth
     day: sys_time.wDay
     hour: sys_time.wHour
     minute: sys_time.wMinute
     second: sys_time.wSecond
     timeZone: [NSTimeZone defaultTimeZone]];
  t = [d timeIntervalSinceReferenceDate];
  [d release];
  return t;
#endif /* __WIN32__ */
}

// Allocation and initializing

+ (id) date
{
  return [[[self alloc] init] autorelease];
}

+ (id) dateWithNaturalLanguageString: (NSString*)string
{
  [self dateWithNaturalLanguageString: string
			       locale: nil];
}

+ (id) dateWithNaturalLanguageString: (NSString*)string
                              locale: (NSDictionary*)locale
{
  NSCharacterSet	*ws;
  NSCharacterSet	*digits;
  NSScanner		*scanner;
  NSString		*tmp;
  NSString		*dto;
  NSArray		*ymw;
  NSMutableArray	*words;
  unsigned		index;
  unsigned		length;
  NSCalendarDate	*theDate;
  BOOL			hadHour = NO;
  BOOL			hadMinute = NO;
  BOOL			hadSecond = NO;
  BOOL			hadDay = NO;
  BOOL			hadMonth = NO;
  BOOL			hadYear = NO;
  BOOL			hadWeekDay = NO;
  int			weekDay = 0;
  int			dayOfWeek = 0;
  int			modMonth = 0;
  int			modYear = 0;
  int			modDay = 0;
  int			D, M, Y;
  int			modWeek;
  int			h = 12;
  int			m = 0;
  int			s = 0;
  unsigned		dtoIndex;

  if (locale == nil)
    locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

  ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  digits = [NSCharacterSet decimalDigitCharacterSet];
  scanner = [NSScanner scannerWithString: string];
  words = [NSMutableArray arrayWithCapacity: 10];

  theDate = (NSCalendarDate*)[NSCalendarDate date];
  Y = [theDate yearOfCommonEra];
  M = [theDate monthOfYear];
  D = [theDate dayOfMonth];
  dayOfWeek = [theDate dayOfWeek];

  [scanner scanCharactersFromSet: ws intoString: 0];
  while ([scanner scanUpToCharactersFromSet: ws intoString: &tmp] == YES)
    {
      [words addObject: tmp];
      [scanner scanCharactersFromSet: ws intoString: 0];
    }

  /*
   *	Scan the array for day specifications and remove them.
   */
  if (hadDay == NO)
    {
      NSString	*tdd = [locale objectForKey: NSThisDayDesignations];
      NSString	*ndd = [locale objectForKey: NSNextDayDesignations];
      NSString	*pdd = [locale objectForKey: NSPriorDayDesignations];
      NSString	*nndd = [locale objectForKey: NSNextNextDayDesignations];

      for (index = 0; hadDay == NO && index < [words count]; index++)
	{
	  tmp = [words objectAtIndex: index];

	  if ([tmp caseInsensitiveCompare: tdd] == NSOrderedSame)
	    {
	      hadDay = YES;
	    }
	  else if ([tmp caseInsensitiveCompare: ndd] == NSOrderedSame)
	    {
	      modDay++;
	      hadDay = YES;
	    }
	  else if ([tmp caseInsensitiveCompare: nndd] == NSOrderedSame)
	    {
	      modDay += 2;
	      hadDay = YES;
	    }
	  else if ([tmp caseInsensitiveCompare: pdd] == NSOrderedSame)
	    {
	      modDay--;
	      hadDay = YES;
	    }
	  if (hadDay)
	    {
	      hadMonth = YES;
	      hadYear = YES;
	      [words removeObjectAtIndex: index];
	    }
	}
    }

  /*
   *	Scan the array for month specifications and remove them.
   */
  if (hadMonth == NO)
    {
      NSArray	*lm = [locale objectForKey: NSMonthNameArray];
      NSArray	*sm = [locale objectForKey: NSShortMonthNameArray];

      for (index = 0; hadMonth == NO && index < [words count]; index++)
	{
	  NSString	*mname;

	  tmp = [words objectAtIndex: index];

	  if ((mname = findInArray(lm, 0, tmp)) != nil)
	    {
	      modMonth += M - [lm indexOfObjectIdenticalTo: mname] - 1;
	      hadMonth = YES;
	    }
	  else if ((mname = findInArray(sm, 0, tmp)) != nil)
	    {
	      modMonth += M - [sm indexOfObjectIdenticalTo: mname] - 1;
	      hadMonth = YES;
	    }

	  if (mname != nil)
	    {
	      hadMonth = YES;
	      [words removeObjectAtIndex: index];
	    }
	}
    }

  /*
   *	Scan the array for weekday specifications and remove them.
   */
  if (hadWeekDay == NO)
    {
      NSArray	*lw = [locale objectForKey: NSWeekDayNameArray];
      NSArray	*sw = [locale objectForKey: NSShortWeekDayNameArray];

      for (index = 0; hadWeekDay == NO && index < [words count]; index++)
	{
	  NSString	*dname;

	  tmp = [words objectAtIndex: index];

	  if ((dname = findInArray(lw, 0, tmp)) != nil)
	    {
	      weekDay = [lw indexOfObjectIdenticalTo: dname];
	    }
	  else if ((dname = findInArray(sw, 0, tmp)) != nil)
	    {
	      weekDay = [sw indexOfObjectIdenticalTo: dname];
	    }

	  if (dname != nil)
	    {
	      hadWeekDay = YES;
	      [words removeObjectAtIndex: index];
	    }
	}
    }

  /*
   *	Scan the array for year month week modifiers and remove them.
   *	Going by the documentation, these modifiers adjust the date by
   *	plus or minus a week, month, or year.
   */
  ymw = [locale objectForKey: NSYearMonthWeekDesignations];
  if (ymw != nil && [ymw count] > 0)
    {
      unsigned	c = [ymw count];
      NSString	*yname = [ymw objectAtIndex: 0];
      NSString	*mname = c > 1 ? [ymw objectAtIndex: 1] : nil;
      NSString	*wname = c > 2 ? [ymw objectAtIndex: 2] : nil;
      NSArray	*early = [locale objectForKey: NSEarlierTimeDesignations];
      NSArray	*later = [locale objectForKey: NSLaterTimeDesignations];

      for (index = 0; index < [words count]; index++)
	{
	  tmp = [words objectAtIndex: index];

	  /*
           *	See if the current word is a year, month, or week.
	   */
	  if (findInArray(ymw, 0, tmp))
	    {
	      BOOL	hadAdjective = NO;
	      int	adjective = 0;
	      NSString	*adj = nil;

	      /*
	       *	See if there is a prefix adjective
	       */
	      if (index > 0)
		{
		  adj = [words objectAtIndex: index - 1];

		  if (findInArray(early, 0, adj))
		    {
		      hadAdjective = YES;
		      adjective = -1;
		    }
		  else if (findInArray(later, 0, adj))
		    {
		      hadAdjective = YES;
		      adjective = 1;
		    }
		  if (hadAdjective)
		    {
		      [words removeObjectAtIndex: --index];
		    }
		}
	      /*
	       *	See if there is a prefix adjective
	       */
	      if (hadAdjective == NO && index < [words count] - 1)
		{
		  NSString	*adj = [words objectAtIndex: index + 1];

		  if (findInArray(early, 0, adj))
		    {
		      hadAdjective = YES;
		      adjective = -1;
		    }
		  else if (findInArray(later, 0, adj))
		    {
		      hadAdjective = YES;
		      adjective = 1;
		    }
		  if (hadAdjective)
		    {
		      [words removeObjectAtIndex: index];
		    }
		}
	      /*
	       *	Record the adjective information.
	       */
	      if (hadAdjective)
		{
		  if ([tmp caseInsensitiveCompare: yname] == NSOrderedSame)
		    {
		      modYear += adjective;
		      hadYear = YES;
		    }
		  else if ([tmp caseInsensitiveCompare: mname] == NSOrderedSame)
		    {
		      modMonth += adjective;
		      hadMonth = YES;
		    }
		  else
		    {
		      if (hadWeekDay)
			{
			  modDay += weekDay - dayOfWeek;
			}
		      modDay += 7*adjective;
		      hadDay = YES;
		      hadMonth = YES;
		      hadYear = YES;
		    }
		}
	      /*
	       *	Remove from list of words.
	       */
	      [words removeObjectAtIndex: index];
	    }
	}
    }

  /* Scan for hour of the day */
  if (hadHour == NO)
    {
      NSArray	*hours = [locale objectForKey: NSHourNameDesignations];
      unsigned	hLimit = [hours count];
      unsigned	hIndex;

      for (index = 0; hadHour == NO && index < [words count]; index++)
	{
	  tmp = [words objectAtIndex: index];

	  for (hIndex = 0; hadHour == NO && hIndex < hLimit; hIndex++)
	    {
	      NSArray	*names;

	      names = [hours objectAtIndex: hIndex];
	      if (findInArray(names, 1, tmp) != nil)
		{
		  h = [[names objectAtIndex: 0] intValue];
		  hadHour = YES;
		  hadMinute = YES;
		  hadSecond = YES;
		}
	    }
	}
    }

  /*
   *	Now re-scan the string for numeric information.
   */

  dto = [locale objectForKey: NSDateTimeOrdering];
  if (dto == nil)
    {
      if (debug)
	NSLog(@"no NSDateTimeOrdering - default to DMYH.\n");
      dto = @"DMYH";
    }
  length = [dto length];
  if (length > 4)
    {
      if (debug)
	NSLog(@"too many characters in NSDateTimeOrdering - truncating.\n");
      length = 4;
    }

  dtoIndex = 0;
  scanner = [NSScanner scannerWithString: string];
  [scanner scanUpToCharactersFromSet: digits intoString: 0];
  while ([scanner scanCharactersFromSet: digits intoString: &tmp] == YES)
    {
      int	num = [tmp intValue];

      if ([scanner scanUpToCharactersFromSet: digits intoString: &tmp] == NO)
	{
	  tmp = nil;
	}
      /*
       *	Numbers separated by colons are a time specification.
       */
      if (tmp && ([tmp characterAtIndex: 0] == (unichar)':'))
	{
	  BOOL	done = NO;

	  do
	    {
	      if (hadHour == NO)
		{
		  if (num > 23)
		    {
		      if (debug)
			NSLog(@"hour (%d) too large - ignored.\n", num);
		      else
			return nil;
		    }
		  else
		    {
		      h = num;
		      m = 0;
		      s = 0;
		      hadHour = YES;
		    }
		}
	      else if (hadMinute == NO)
		{
		  if (num > 59)
		    {
		      if (debug)
			NSLog(@"minute (%d) too large - ignored.\n", num);
		      else
			return nil;
		    }
		  else
		    {
		      m = num;
		      s = 0;
		      hadMinute = YES;
		    }
		}
	      else if (hadSecond == NO)
		{
		  if (num > 59)
		    {
		      if (debug)
			NSLog(@"second (%d) too large - ignored.\n", num);
		      else
			return nil;
		    }
		  else
		    {
		      s = num;
		      hadSecond = YES;
		    }
		}
	      else
		{
		  if (debug)
		    NSLog(@"odd time spec - excess numbers ignored.\n");
		}

	      done = YES;
	      if (tmp && ([tmp characterAtIndex: 0] == (unichar)':'))
		{
		  if ([scanner scanCharactersFromSet: digits intoString: &tmp])
		    {
		      num = [tmp intValue];
		      done = NO;
		      if ([scanner scanUpToCharactersFromSet: digits
						  intoString: &tmp] == NO)
			{
			  tmp = nil;
			}
		    }
		}
	    }
	  while (done == NO);
	}
      else
	{
	  BOOL	mustSkip = YES;

	  while ((dtoIndex < [dto length]) && (mustSkip == YES))
	    {
	      switch ([dto characterAtIndex: dtoIndex])
		{
		  case 'D':
		    if (hadDay)
		      dtoIndex++;
		    else
		      mustSkip = NO;
		    break;

		  case 'M':
		    if (hadMonth)
		      dtoIndex++;
		    else
		      mustSkip = NO;
		    break;
			
		  case 'Y':
		    if (hadYear)
		      dtoIndex++;
		    else
		      mustSkip = NO;
		    break;
			
		  case 'H':
		    if (hadHour)
		      dtoIndex++;
		    else
		      mustSkip = NO;
		    break;
			
		  default:
		    dtoIndex++;
		    if (debug)
		      NSLog(@"odd char (unicode %d) in NSDateTimeOrdering.\n",
			    [dto characterAtIndex: index]);
		    break;
		}
	    }
	  if (dtoIndex >= [dto length])
	    {
	      if (debug)
		NSLog(@"odd date specification - excess numbers ignored.\n");
	      break;
	    }
	  switch ([dto characterAtIndex: dtoIndex])
	    {
	      case 'D':
		if (num < 1)
		  {
		    if (debug)
		      NSLog(@"day (0) too small - ignored.\n");
		    else
		      return nil;
		  }
		else if (num > 31)
		  {
		    if (debug)
		      NSLog(@"day (%d) too large - ignored.\n", num);
		    else
		      return nil;
		  }
		else
		  {
		    D = num;
		    hadDay = YES;
		  }
		break;
	      case 'M':
		if (num < 1)
		  {
		    if (debug)
		      NSLog(@"month (0) too small - ignored.\n");
		    else
		      return nil;
		  }
		else if (num > 12)
		  {
		    if (debug)
		      NSLog(@"month (%d) too large - ignored.\n", num);
		    else
		      return nil;
		  }
		else
		  {
		    M = num;
		    hadMonth = YES;
		  }
		break;
	      case 'Y':
		if (num < 100)
		  {
		    if (num < 70)
		      {
			Y = num + 2000;
		      }
		    else
		      {
			Y = num + 1900;
		      }
		    if (debug)
		      NSLog(@"year (%d) adjusted to %d.\n", num, Y);
		  }
		else
		  {
		    Y = num;
		  }
		hadYear = YES;
		break;
	      case 'H':
		{
		  BOOL	shouldIgnore = NO;

		  /*
		   *	Check the next text to see if it is an am/pm
		   *	designation.
		   */
		  if (tmp)
		    {
		      NSArray	*ampm;
		      NSString	*mod;

		      ampm = [locale objectForKey: NSAMPMDesignation];
		      mod = findInArray(ampm, 0, tmp);
		      if (mod)
			{
			  if (num > 11)
			    {
			      if (debug)
				NSLog(@"hour (%d) too large - ignored.\n",
				      num);
			      else
				return nil;
			      shouldIgnore = YES;
			    }
			  else if (mod == [ampm objectAtIndex: 1])
			    {
			      num += 12;
			    }
			}
		    }
		  if (shouldIgnore == NO)
		    {
		      if (num > 23)
			{
			  if (debug)
			    NSLog(@"hour (%d) too large - ignored.\n", num);
			  else
			    return nil;
			}
		      else
			{
			  hadHour = YES;
			  h = num;
			}
		    }
		  break;
		}
	      default:
		if (debug)
		  NSLog(@"unexpected char (unicode%d) in NSDateTimeOrdering.\n",
		    [dto characterAtIndex: index]);
		break;
	    }
	}
    }
  
  /*
   *	If we had no date or time information - we give up, otherwise
   *	we can use reasonable defaults for any missing info.
   *	Missing date => today
   *	Missing time => 12:00
   *	If we had a week/month/year modifier without a day, we assume today.
   *	If we had a day name without any more day detail - adjust to that
   *	day this week.
   */
  if (hadDay == NO && hadWeekDay == YES)
    {
      modDay += weekDay - dayOfWeek;
      hadDay = YES;
    }
  if (hadDay == NO && hadHour == NO)
    {
      if (modDay == NO && modMonth == NO && modYear == NO)
	{
	  return nil;
	}
    }

  /*
   *	Build a calendar date we can adjust easily.
   */
  theDate = [NSCalendarDate dateWithYear: Y
				   month: M
				     day: D
				    hour: h
				  minute: m
				  second: s
				timeZone: [NSTimeZone defaultTimeZone]];

  /*
   *	Adjust the date by year month or days if necessary.
   */
  if (modYear || modMonth || modDay)
    {
      theDate = [theDate dateByAddingYears: modYear
				    months: modMonth
				      days: modDay
				     hours: 0
				   minutes: 0
				   seconds: 0];
    }
  if (hadWeekDay && [theDate dayOfWeek] != weekDay)
    {
      if (debug)
	NSLog(@"Date resulted in wrong day of week.\n");
      return nil;
    }
  return [self dateWithTimeIntervalSinceReferenceDate:
		[theDate timeIntervalSinceReferenceDate]];
}

+ (id) dateWithString: (NSString*)description
{
  return [[[self alloc] initWithString: description]  autorelease];
}

+ (id) dateWithTimeIntervalSinceNow: (NSTimeInterval)seconds
{
  return [[[self alloc] initWithTimeIntervalSinceNow: seconds]  autorelease];
}

+ (id)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds
{
  return [[[self alloc] initWithTimeIntervalSinceReferenceDate: 
		       UNIX_REFERENCE_INTERVAL + seconds] autorelease];
}

+ (id) dateWithTimeIntervalSinceReferenceDate: (NSTimeInterval)seconds
{
  return [[[self alloc] initWithTimeIntervalSinceReferenceDate: seconds]
	   autorelease];
}

+ (id) distantFuture
{
  static id df = nil;
  if (!df)
    df = [[self alloc] initWithTimeIntervalSinceReferenceDate: DISTANT_FUTURE];
  return df;
}

+ (id) distantPast
{
  static id dp = nil;
  if (!dp)
    dp = [[self alloc] initWithTimeIntervalSinceReferenceDate: DISTANT_PAST];
  return dp;
}

- (id) copyWithZone:(NSZone*)zone
{
  if (NSShouldRetainWithZone(self, zone))
    return [self retain];
  else
    return NSCopyObject(self, 0, zone);
}

- (Class) classForConnectedCoder: aRmc
{
  /* Make sure that Connection's always send us bycopy,
     i.e. as our own class, not a Proxy class. */
  return [self class];
}

- (Class) classForPortCoder
{
  return [self class];
}
- replacementObjectForPortCoder: aRmc
{
  return self;
}

- (void) encodeWithCoder:(NSCoder*)coder
{
  [super encodeWithCoder:coder];
  [coder encodeValueOfObjCType:@encode(NSTimeInterval) at:&seconds_since_ref];
}

- (id) initWithCoder:(NSCoder*)coder
{
  self = [super initWithCoder:coder];
  [coder decodeValueOfObjCType:@encode(NSTimeInterval) at:&seconds_since_ref];
  return self;
}

- (id) init
{
  return [self initWithTimeIntervalSinceReferenceDate:
		 [[self class] timeIntervalSinceReferenceDate]];
}

- (id) initWithString: (NSString*)description
{
  // Easiest to just have NSCalendarDate do the work for us
  NSCalendarDate *d = [NSCalendarDate alloc];
  [d initWithString: description];
  [self initWithTimeIntervalSinceReferenceDate:
	[d timeIntervalSinceReferenceDate]];
  [d release];
  return self;
}

- (id) initWithTimeInterval: (NSTimeInterval)secsToBeAdded
		       sinceDate: (NSDate*)anotherDate;
{
  // Get the other date's time, add the secs and init thyself
  return [self initWithTimeIntervalSinceReferenceDate:
	       [anotherDate timeIntervalSinceReferenceDate] + secsToBeAdded];
}

- (id) initWithTimeIntervalSinceNow: (NSTimeInterval)secsToBeAdded;
{
  // Get the current time, add the secs and init thyself
  return [self initWithTimeIntervalSinceReferenceDate:
	       [[self class] timeIntervalSinceReferenceDate] + secsToBeAdded];
}

- (id)initWithTimeIntervalSince1970:(NSTimeInterval)seconds
{
  return [self initWithTimeIntervalSinceReferenceDate: 
		       UNIX_REFERENCE_INTERVAL + seconds];
}

- (id) initWithTimeIntervalSinceReferenceDate: (NSTimeInterval)secs
{
  [super init];
  seconds_since_ref = secs;
  return self;
}

// Converting to NSCalendar

- (NSCalendarDate *) dateWithCalendarFormat: (NSString*)formatString
				   timeZone: (NSTimeZone*)timeZone
{
  NSCalendarDate *d = [NSCalendarDate alloc];
  [d initWithTimeIntervalSinceReferenceDate: seconds_since_ref];
  [d setCalendarFormat: formatString];
  [d setTimeZone: timeZone];
  return [d autorelease];
}

// Representing dates

- (NSString*) description
{
  // Easiest to just have NSCalendarDate do the work for us
  NSString *s;
  NSCalendarDate *d = [NSCalendarDate alloc];
  [d initWithTimeIntervalSinceReferenceDate: seconds_since_ref];
  s = [d description];
  [d release];
  return s;
}

- (NSString*) descriptionWithCalendarFormat: (NSString*)format
				   timeZone: (NSTimeZone*)aTimeZone
				     locale: (NSDictionary*)l
{
  // Easiest to just have NSCalendarDate do the work for us
  NSString *s;
  NSCalendarDate *d = [NSCalendarDate alloc];
  id f;

  [d initWithTimeIntervalSinceReferenceDate: seconds_since_ref];
  if (!format)
    f = [d calendarFormat];
  else
    f = format;
  if (aTimeZone)
    [d setTimeZone: aTimeZone];

  s = [d descriptionWithCalendarFormat: f locale: l];
  [d release];
  return s;
}

- (NSString *) descriptionWithLocale: (NSDictionary *)locale
{
  // Easiest to just have NSCalendarDate do the work for us
  NSString *s;
  NSCalendarDate *d = [NSCalendarDate alloc];
  [d initWithTimeIntervalSinceReferenceDate: seconds_since_ref];
  s = [d descriptionWithLocale: locale];
  [d release];
  return s;
}

// Adding and getting intervals

- (id) addTimeInterval: (NSTimeInterval)seconds
{
  /* xxx We need to check for overflow? */
  return [[self class] dateWithTimeIntervalSinceReferenceDate:
		       seconds_since_ref + seconds];
}

- (NSTimeInterval) timeIntervalSince1970
{
  return seconds_since_ref - UNIX_REFERENCE_INTERVAL;
}

- (NSTimeInterval) timeIntervalSinceDate: (NSDate*)otherDate
{
  return seconds_since_ref - [otherDate timeIntervalSinceReferenceDate];
}

- (NSTimeInterval) timeIntervalSinceNow
{
  NSTimeInterval now = [[self class] timeIntervalSinceReferenceDate];
  return seconds_since_ref - now;
}

- (NSTimeInterval) timeIntervalSinceReferenceDate
{
  return seconds_since_ref;
}

// Comparing dates

- (NSComparisonResult) compare: (NSDate*)otherDate
{
  if (seconds_since_ref > [otherDate timeIntervalSinceReferenceDate])
    return NSOrderedDescending;
		
  if (seconds_since_ref < [otherDate timeIntervalSinceReferenceDate])
    return NSOrderedAscending;
		
  return NSOrderedSame;
}

- (NSDate*) earlierDate: (NSDate*)otherDate
{
  if (seconds_since_ref > [otherDate timeIntervalSinceReferenceDate])
    return otherDate;
  return self;
}

- (BOOL) isEqual: (id)other
{
  if ([other isKindOf: [NSDate class]] 
      && 1.0 > ABS(seconds_since_ref - [other timeIntervalSinceReferenceDate]))
    return YES;
  return NO;
}		

- (BOOL) isEqualToDate: (NSDate*)other
{
  if (1.0 > ABS(seconds_since_ref - [other timeIntervalSinceReferenceDate]))
    return YES;
  return NO;
}		

- (NSDate*) laterDate: (NSDate*)otherDate
{
  if (seconds_since_ref < [otherDate timeIntervalSinceReferenceDate])
    return otherDate;
  return self;
}

@end
