/** Implementation for NSCalendarDate for GNUstep
   Copyright (C) 1996, 1998, 1999, 2000, 2002 Free Software Foundation, Inc.

   Author:  Scott Christley <scottc@net-community.com>
   Date: October 1996

   Author: Richard Frith-Macdonald <rfm@gnu.org>
   Date: September 2002

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

   <title>NSCalendarDate class reference</title>
   $Date$ $Revision$
   */

#include <config.h>
#include <math.h>
#include <Foundation/NSObjCRuntime.h>
#include <Foundation/NSData.h>
#include <Foundation/NSDate.h>
#include <Foundation/NSCalendarDate.h>
#include <Foundation/NSTimeZone.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSString.h>
#include <Foundation/NSCoder.h>
#include <Foundation/NSException.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSDebug.h>
#include <base/GSObjCRuntime.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include "GSPrivate.h"

// Absolute Gregorian date for NSDate reference date Jan 01 2001
//
//  N = 1;                 // day of month
//  N = N + 0;             // days in prior months for year
//  N = N +                // days this year
//    + 365 * (year - 1)   // days in previous years ignoring leap days
//    + (year - 1)/4       // Julian leap days before this year...
//    - (year - 1)/100     // ...minus prior century years...
//    + (year - 1)/400     // ...plus prior years divisible by 400

#define GREGORIAN_REFERENCE 730486

@class	GSTimeZone;
@class	GSAbsTimeZone;

static NSString	*cformat = @"%Y-%m-%d %H:%M:%S %z";

static NSTimeZone	*localTZ = nil;

static Class	absClass;
static Class	dstClass;

static SEL		offSEL;
static int (*offIMP)(id, SEL, id);
static int (*absOffIMP)(id, SEL, id);
static int (*dstOffIMP)(id, SEL, id);

static SEL		abrSEL;
static NSString* (*abrIMP)(id, SEL, id);
static NSString* (*absAbrIMP)(id, SEL, id);
static NSString* (*dstAbrIMP)(id, SEL, id);


/*
 * Return the offset from GMT for a date in a timezone ...
 * Optimize for the local timezone, and less so for the other
 * base library time zone classes.
 */
static inline int
offset(NSTimeZone *tz, NSDate *d)
{
  if (tz == nil)
    {
      return 0;
    }
  if (tz == localTZ && offIMP != 0)
    {
      return (*offIMP)(tz, offSEL, d);
    }
  else
    {
      Class	c = GSObjCClass(tz);

      if (c == dstClass && dstOffIMP != 0)
	{
	  return (*dstOffIMP)(tz, offSEL, d);
	}
      if (c == absClass && absOffIMP != 0)
	{
	  return (*absOffIMP)(tz, offSEL, d);
	}
      return [tz secondsFromGMTForDate: d];
    }
}

/*
 * Return the offset from GMT for a date in a timezone ...
 * Optimize for the local timezone, and less so for the other
 * base library time zone classes.
 */
static inline NSString*
abbrev(NSTimeZone *tz, NSDate *d)
{
  if (tz == nil)
    {
      return @"GMT";
    }
  if (tz == localTZ && abrIMP != 0)
    {
      return (*abrIMP)(tz, abrSEL, d);
    }
  else
    {
      Class	c = GSObjCClass(tz);

      if (c == dstClass && dstAbrIMP != 0)
	{
	  return (*dstAbrIMP)(tz, abrSEL, d);
	}
      if (c == absClass && absAbrIMP != 0)
	{
	  return (*absAbrIMP)(tz, abrSEL, d);
	}
      return [tz abbreviationForDate: d];
    }
}

static inline unsigned int
lastDayOfGregorianMonth(int month, int year)
{
  switch (month)
    {
      case 2:
	if ((((year % 4) == 0) && ((year % 100) != 0))
	  || ((year % 400) == 0))
	  return 29;
	else
	  return 28;
      case 4:
      case 6:
      case 9:
      case 11: return 30;
      default: return 31;
    }
}

static inline int
absoluteGregorianDay(int day, int month, int year)
{
  int m, N;

  N = day;   // day of month
  for (m = month - 1;  m > 0; m--) // days in prior months this year
    N = N + lastDayOfGregorianMonth(m, year);
  return
    (N                    // days this year
     + 365 * (year - 1)   // days in previous years ignoring leap days
     + (year - 1)/4       // Julian leap days before this year...
     - (year - 1)/100     // ...minus prior century years...
     + (year - 1)/400);   // ...plus prior years divisible by 400
}

static int dayOfCommonEra(NSTimeInterval when)
{
  double a;
  int r;

  // Get reference date in terms of days
  a = when / 86400.0;
  // Offset by Gregorian reference
  a += GREGORIAN_REFERENCE;
  r = (int)a;
  return r;
}

static void
gregorianDateFromAbsolute(int abs, int *day, int *month, int *year)
{
  // Search forward year by year from approximate year
  *year = abs/366;
  while (abs >= absoluteGregorianDay(1, 1, (*year)+1))
    {
      (*year)++;
    }
  // Search forward month by month from January
  (*month) = 1;
  while (abs > absoluteGregorianDay(lastDayOfGregorianMonth(*month, *year),
    *month, *year))
    {
      (*month)++;
    }
  *day = abs - absoluteGregorianDay(1, *month, *year) + 1;
}

/**
 * Convert a broken out time specification into a time interval
 * since the reference date.<br />
 * External - so NSDate and others can use it.
 */
NSTimeInterval
GSTime(int day, int month, int year, int hour, int minute, int second, int mil)
{
  NSTimeInterval	a;

  a = (NSTimeInterval)absoluteGregorianDay(day, month, year);

  // Calculate date as GMT
  a -= GREGORIAN_REFERENCE;
  a = (NSTimeInterval)a * 86400;
  a += hour * 3600;
  a += minute * 60;
  a += second;
  a += mil/1000.0;
  return a;
}

/**
 * Convert a time interval since the reference date into broken out
 * elements.<br />
 * External - so NSDate and others can use it.
 */
void
GSBreakTime(NSTimeInterval when, int *year, int *month, int *day,
  int *hour, int *minute, int *second, int *mil)
{
  int h, m, dayOfEra;
  double a, b, c, d;

  // Get reference date in terms of days
  a = when / 86400.0;
  // Offset by Gregorian reference
  a += GREGORIAN_REFERENCE;
  // result is the day of common era.
  dayOfEra = (int)a;

  // Calculate year, month, and day
  gregorianDateFromAbsolute(dayOfEra, day, month, year);

  // Calculate hour, minute, and seconds
  d = dayOfEra - GREGORIAN_REFERENCE;
  d *= 86400;
  a = abs(d - when);
  b = a / 3600;
  *hour = (int)b;
  h = *hour;
  h = h * 3600;
  b = a - h;
  b = b / 60;
  *minute = (int)b;
  m = *minute;
  m = m * 60;
  c = a - h - m;
  *second = (int)c;
  *mil = (a - h - m - c) * 1000;
}

@class	NSGDate;

/**
 * An [NSDate] subclass which understands about timezones and provides
 * methods for dealing with date and time information by calendar and
 * with hours minutes and seconds.
 */
@implementation NSCalendarDate

+ (void) initialize
{
  if (self == [NSCalendarDate class])
    {
      [self setVersion: 1];
      localTZ = RETAIN([NSTimeZone localTimeZone]);

      dstClass = [GSTimeZone class];
      absClass = [GSAbsTimeZone class];

      offSEL = @selector(secondsFromGMTForDate:);
      offIMP = (int (*)(id,SEL,id))
	[localTZ methodForSelector: offSEL];
      dstOffIMP = (int (*)(id,SEL,id))
	[dstClass instanceMethodForSelector: offSEL];
      absOffIMP = (int (*)(id,SEL,id))
	[absClass instanceMethodForSelector: offSEL];

      abrSEL = @selector(abbreviationForDate:);
      abrIMP = (NSString* (*)(id,SEL,id))
	[localTZ methodForSelector: abrSEL];
      dstAbrIMP = (NSString* (*)(id,SEL,id))
	[dstClass instanceMethodForSelector: abrSEL];
      absAbrIMP = (NSString* (*)(id,SEL,id))
	[absClass instanceMethodForSelector: abrSEL];

      GSObjCAddClassBehavior(self, [NSGDate class]);
    }
}

/**
 * Return an NSCalendarDate for the current date and time using the
 * default timezone.
 */
+ (id) calendarDate
{
  id	d = [[self alloc] init];

  return AUTORELEASE(d);
}

/**
 * Return an NSCalendarDate generated from the supplied description
 * using the format specified for parsing that string.<br />
 * Calls -initWithString:calendarFormat: to create the date.
 */
+ (id) dateWithString: (NSString *)description
       calendarFormat: (NSString *)format
{
  NSCalendarDate *d = [[self alloc] initWithString: description
				    calendarFormat: format];
  return AUTORELEASE(d);
}

/**
 * Return an NSCalendarDate generated from the supplied description
 * using the format specified for parsing that string and interpreting
 * it according to the dictionary specified.<br />
 * Calls -initWithString:calendarFormat:locale: to create the date.
 */
+ (id) dateWithString: (NSString *)description
       calendarFormat: (NSString *)format
	       locale: (NSDictionary *)dictionary
{
  NSCalendarDate *d = [[self alloc] initWithString: description
				    calendarFormat: format
				    locale: dictionary];
  return AUTORELEASE(d);
}

/**
 * Creates and returns an NSCalendarDate from the specified values 
 * by calling -initWithYear:month:day:hour:minute:second:timeZone:
 */
+ (id) dateWithYear: (int)year
	      month: (unsigned int)month
	        day: (unsigned int)day
	       hour: (unsigned int)hour
	     minute: (unsigned int)minute
	     second: (unsigned int)second
	   timeZone: (NSTimeZone *)aTimeZone
{
  NSCalendarDate *d = [[self alloc] initWithYear: year
					   month: month
					     day: day
					    hour: hour
					  minute: minute
					  second: second
					timeZone: aTimeZone];
  return AUTORELEASE(d);
}

/**
 * Creates and returns a new NSCalendarDate object by taking the
 * value of the receiver and adding the interval in seconds specified.
 */
- (id) addTimeInterval: (NSTimeInterval)seconds
{
  id newObj = [[self class] dateWithTimeIntervalSinceReferenceDate:
     [self timeIntervalSinceReferenceDate] + seconds];
	
  [newObj setTimeZone: [self timeZoneDetail]];

  return newObj;
}

- (Class) classForCoder
{
  return [self class];
}

- (id) replacementObjectForPortCoder: (NSPortCoder*)aRmc
{
  return self;
}

- (void) encodeWithCoder: (NSCoder*)coder
{
  [coder encodeValueOfObjCType: @encode(NSTimeInterval)
			    at: &_seconds_since_ref];
  [coder encodeObject: _calendar_format];
  [coder encodeObject: _time_zone];
}

- (id) initWithCoder: (NSCoder*)coder
{
  [coder decodeValueOfObjCType: @encode(NSTimeInterval)
			    at: &_seconds_since_ref];
  [coder decodeValueOfObjCType: @encode(id) at: &_calendar_format];
  [coder decodeValueOfObjCType: @encode(id) at: &_time_zone];
  return self;
}

- (void) dealloc
{
  RELEASE(_calendar_format);
  RELEASE(_time_zone);
  [super dealloc];
}

/**
 * Initializes an NSCalendarDate using the specified description and the
 * default calendar format and locale.<br />
 * Calls -initWithString:calendarFormat:locale:
 */
- (id) initWithString: (NSString *)description
{
  // +++ What is the locale?
  return [self initWithString: description
	       calendarFormat: cformat
		       locale: nil];
}

/**
 * Initializes an NSCalendarDate using the specified description and format
 * string interpreted in the default locale.<br />
 * Calls -initWithString:calendarFormat:locale:
 */
- (id) initWithString: (NSString *)description
       calendarFormat: (NSString *)format
{
  // ++ What is the locale?
  return [self initWithString: description
	       calendarFormat: format
		       locale: nil];
}

/*
 * read up to the specified number of characters, terminating at a non-digit
 * except for leading whitespace characters.
 */
static inline int getDigits(const char *from, char *to, int limit)
{
  int	i = 0;
  int	j = 0;
  BOOL	foundDigit = NO;

  while (i < limit)
    {
      if (isdigit(from[i]))
	{
	  to[j++] = from[i];
	  foundDigit = YES;
	}
      else if (isspace(from[i]))
	{
	  if (foundDigit == YES)
	    {
	      break;
	    }
	}
      else
	{
	  break;
	}
      i++;
    }
  to[j] = '\0';
  return i;
}

#define	hadY	1
#define	hadM	2
#define	hadD	4
#define	hadh	8
#define	hadm	16
#define	hads	32
#define	hadw	64

/**
 * Initializes an NSCalendarDate using the specified description and format
 * string interpreted in the given locale.<br />
 * Format specifiers are -
 * <list>
 *   <item>
 *     %%   literal % character
 *   </item>
 *   <item>
 *     %a   abbreviated weekday name according to locale
 *   </item>
 *   <item>
 *     %A   full weekday name according to locale
 *   </item>
 *   <item>
 *     %b   abbreviated month name according to locale
 *   </item>
 *   <item>
 *     %B   full month name according to locale
 *   </item>
 *   <item>
 *     %c   same as '%X %x'
 *   </item>
 *   <item>
 *     %d   day of month as decimal number
 *   </item>
 *   <item>
 *     %e   same as %d without leading zero (you get a leading space instead)
 *   </item>
 *   <item>
 *     %F   milliseconds as a decimal number
 *   </item>
 *   <item>
 *     %H   hour as a decimal number using 24-hour clock
 *   </item>
 *   <item>
 *     %I   hour as a decimal number using 12-hour clock
 *   </item>
 *   <item>
 *     %j   day of year as a decimal number
 *   </item>
 *   <item>
 *     %m   month as decimal number
 *   </item>
 *   <item>
 *     %M   minute as decimal number
 *   </item>
 *   <item>
 *     %p   'am' or 'pm'
 *   </item>
 *   <item>
 *     %S   second as decimal number
 *   </item>
 *   <item>
 *     %U   week of the current year as decimal number (Sunday first day)
 *   </item>
 *   <item>
 *     %W   week of the current year as decimal number (Monday first day)
 *   </item>
 *   <item>
 *     %w   day of the week as decimal number (Sunday = 0)
 *   </item>
 *   <item>
 *     %x   date with date representation for locale
 *   </item>
 *   <item>
 *     %X   time with time representation for locale
 *   </item>
 *   <item>
 *     %y   year as a decimal number without century 
 *   </item>
 *   <item>
 *     %Y   year as a decimal number with century
 *   </item>
 *   <item>
 *     %z   time zone offset in hours and minutes from GMT (HHMM)
 *   </item>
 *   <item>
 *     %Z   time zone abbreviation
 *   </item>
 * </list>
 */
- (id) initWithString: (NSString *)description 
       calendarFormat: (NSString *)fmt
               locale: (NSDictionary *)locale
{
  // If description does not match this format exactly, this method returns nil 
  if ([description length] == 0)
    {
      // Autorelease self because it isn't done by the calling function
      // [[NSCalendarDate alloc] initWithString:calendarFormat:locale:];
      AUTORELEASE(self);
      return nil;
    }
  else
    {
      int		year = 0, month = 1, day = 1;
      int		hour = 0, min = 0, sec = 0;
      NSTimeZone	*tz = localTZ;
      BOOL		ampm = NO;
      BOOL		twelveHrClock = NO; 
      int		julianWeeks = -1, weekStartsMonday = 0, dayOfWeek = -1;
      const char	*source = [description cString];
      unsigned		sourceLen = strlen(source);
      unichar		*format;
      unsigned		formatLen;
      unsigned		formatIdx = 0;
      unsigned		sourceIdx = 0;
      char		tmpStr[20];
      unsigned int	tmpIdx;
      unsigned		had = 0;
      unsigned int	pos;
      BOOL		hadPercent = NO;
      NSString		*dForm;
      NSString		*tForm;
      NSString		*TForm;
      NSMutableData	*fd;
      BOOL		changedFormat = NO;
      
      if (locale == nil)
	{
	  locale = GSUserDefaultsDictionaryRepresentation();
	}
      if (fmt == nil)
	{
	  fmt = [locale objectForKey: NSTimeDateFormatString];
	  if (fmt == nil)
	    fmt = @"";
	}

      TForm = [locale objectForKey: NSTimeDateFormatString];
      if (TForm == nil)
	TForm = @"%X %x";
      dForm = [locale objectForKey: NSShortDateFormatString];
      if (dForm == nil)
	dForm = @"%y-%m-%d";
      tForm = [locale objectForKey: NSTimeFormatString];
      if (tForm == nil)
	tForm = @"%H-%M-%S";

      /*
       * Get format into a buffer, leaving room for expansion in case it has
       * escapes that need to be converted.
       */
      formatLen = [fmt length];
      fd = [[NSMutableData alloc]
	initWithLength: (formatLen + 32) * sizeof(unichar)];
      format = (unichar*)[fd mutableBytes];
      [fmt getCharacters: format];

      /*
       * Expand any sequences to their basic components.
       */
      for (pos = 0; pos < formatLen; pos++)
	{
	  unichar	c = format[pos];

	  if (c == '%')
	    {
	      if (hadPercent == YES)
		{
		  hadPercent = NO;
		}
	      else
		{
		  hadPercent = YES;
		}
	    }
	  else
	    {
	      if (hadPercent == YES)
		{
		  NSString	*sub = nil;

		  if (c == 'c')
		    {
		      sub = TForm;
		    }
		  else if (c == 'R')
		    {
		      sub = @"%H:%M";
		    }
		  else if (c == 'r')
		    {
		      sub = @"%I:%M:%S %p";
		    }
		  else if (c == 'X')
		    {
		      sub = tForm;
		    }
		  else if (c == 'x')
		    {
		      sub = dForm;
		    }

		  if (sub != nil)
		    {
		      unsigned	sLen = [sub length];
		      int	i;

		      if (sLen > 2)
			{
			  [fd setLength:
			    (formatLen + sLen - 2) * sizeof(unichar)];
			  format = (unichar*)[fd mutableBytes];
			  for (i = formatLen-1; i > (int)pos; i--)
			    {
			      format[i+sLen-2] = format[i];
			    }
			}
		      else
			{
			  for (i = pos+1; i < (int)formatLen; i++)
			    {
			      format[i+sLen-2] = format[i];
			    }
			  [fd setLength:
			    (formatLen + sLen - 2) * sizeof(unichar)];
			  format = (unichar*)[fd mutableBytes];
			}
		      [sub getCharacters: &format[pos-1]];
		      formatLen += sLen - 2;
		      changedFormat = YES;
		      pos -= 2;	// Re-parse the newly substituted data.
		    }
		}
	      hadPercent = NO;
	    }
	}

      /*
       * Set up calendar format.
       */
      if (changedFormat == YES)
	{
	  fmt = [NSString stringWithCharacters: format length: formatLen];
	}
      ASSIGN(_calendar_format, fmt);

      //
      // WARNING:
      //   %F, does NOT work.
      //    and the underlying call has granularity to the second.
      //   -Most locale stuff is dubious at best.
      //   -Long day and month names depend on a non-alpha character after the
      //    last digit to work.
      //

      while (formatIdx < formatLen)
	{
	  if (format[formatIdx] != '%')
	    {
	      // If it's not a format specifier, ignore it.
	      if (isspace(format[formatIdx]))
		{
		  // Skip any amount of white space.
		  while (source[sourceIdx] != 0 && isspace(source[sourceIdx]))
		    {
		      sourceIdx++;
		    }
		}
	      else
		{
		  if (sourceIdx < sourceLen)
		    {
		      if (source[sourceIdx] != format[formatIdx])
			{
			  NSLog(@"Expected literal '%c' but got '%c' parsing"
			    @"'%@' using '%@'", format[formatIdx],
			    source[sourceIdx], description, fmt);
			}
		      sourceIdx++;
		    }
		}
	    }
	  else
	    {
	      // Skip '%'
	      formatIdx++;

	      switch (format[formatIdx])
		{
		  case '%':
		    // skip literal %
		    if (sourceIdx < sourceLen)
		      {
			if (source[sourceIdx] != '%')
			  {
			    NSLog(@"Expected literal '%%' but got '%c' parsing"
			      @"'%@' using '%@'", source[sourceIdx],
			      description, fmt);
			  }
			sourceIdx++;
		      }
		    break;

		  case 'a':
		    // Are Short names three chars in all locales?????
		    tmpStr[0] = toupper(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[1] = tolower(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[2] = tolower(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[3] = '\0';
		    {
		      NSString	*currDay;
		      NSArray	*dayNames;

		      currDay = [NSString stringWithCString: tmpStr];
		      dayNames = [locale objectForKey: NSShortWeekDayNameArray];
		      for (tmpIdx = 0; tmpIdx < 7; tmpIdx++)
			{
			  if ([[dayNames objectAtIndex: tmpIdx] isEqual:
			    currDay] == YES)
			    {
			      break;
			    }
			}
		      dayOfWeek = tmpIdx; 
		      had |= hadw;
		    }
		    break;

		  case 'A':
		    for (tmpIdx = sourceIdx; tmpIdx < sourceLen; tmpIdx++)
		      {
			if (isalpha(source[tmpIdx]))
			  {
			    tmpStr[tmpIdx - sourceIdx] = source[tmpIdx];
			  }
			else
			  {
			    break;
			  }
		      }
		    tmpStr[tmpIdx - sourceIdx] = '\0';
		    sourceIdx += tmpIdx - sourceIdx;
		    {
		      NSString	*currDay;
		      NSArray	*dayNames;

		      currDay = [NSString stringWithCString: tmpStr];
		      dayNames = [locale objectForKey: NSWeekDayNameArray];
		      for (tmpIdx = 0; tmpIdx < 7; tmpIdx++)
			{
			  if ([[dayNames objectAtIndex: tmpIdx] isEqual:
			    currDay] == YES)
			    {
			      break;
			    }
			}
		      dayOfWeek = tmpIdx;
		      had |= hadw;
		    }
		    break;

		  case 'b':
		    // Are Short names three chars in all locales?????
		    tmpStr[0] = toupper(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[1] = tolower(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[2] = tolower(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[3] = '\0';
		    {
		      NSString	*currMonth;
		      NSArray	*monthNames;

		      currMonth = [NSString stringWithCString: tmpStr];
		      monthNames = [locale objectForKey: NSShortMonthNameArray];

		      for (tmpIdx = 0; tmpIdx < 12; tmpIdx++)
			{
			  if ([[monthNames objectAtIndex: tmpIdx]
				    isEqual: currMonth] == YES)
			    {
			      break;
			    }
			}
		      month = tmpIdx+1;
		      had |= hadM;
		    }
		    break;

		  case 'B':
		    for (tmpIdx = sourceIdx; tmpIdx < sourceLen; tmpIdx++)
		      {
			if (isalpha(source[tmpIdx]))
			  {
			    tmpStr[tmpIdx - sourceIdx] = source[tmpIdx];
			  }
			else
			  {
			    break;
			  }
		      }
		    tmpStr[tmpIdx - sourceIdx] = '\0';
		    sourceIdx += tmpIdx - sourceIdx;
		    {
		      NSString	*currMonth;
		      NSArray	*monthNames;

		      currMonth = [NSString stringWithCString: tmpStr];
		      monthNames = [locale objectForKey: NSMonthNameArray];

		      for (tmpIdx = 0; tmpIdx < 12; tmpIdx++)
			{
			  if ([[monthNames objectAtIndex: tmpIdx]
				    isEqual: currMonth] == YES)
			    {
			      break;
			    }
			}
		      month = tmpIdx+1;
		      had |= hadM;
		    }
		    break;

		  case 'd': // fall through
		  case 'e':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    day = atoi(tmpStr);
		    had |= hadD;
		    break;

		  case 'F':
		    NSLog(@"%F format ignored when creating date");
		    break;

		  case 'I': // fall through
		    twelveHrClock = YES;
		  case 'H':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    hour = atoi(tmpStr);
		    had |= hadh;
		    break;

		  case 'j':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 3);
		    day = atoi(tmpStr);
		    had |= hadD;
		    break;

		  case 'm':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    month = atoi(tmpStr);
		    had |= hadM;
		    break;

		  case 'M':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    min = atoi(tmpStr);
		    had |= hadm;
		    break;

		  case 'p':
		    // Questionable assumption that all am/pm indicators are 2
		    // characters and in upper case....
		    tmpStr[0] = toupper(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[1] = toupper(source[sourceIdx]);
		    if (sourceIdx < sourceLen)
		      sourceIdx++;
		    tmpStr[2] = '\0';
		    {
		      NSString	*currAMPM;
		      NSArray	*amPMNames;

		      currAMPM = [NSString stringWithCString: tmpStr];
		      amPMNames = [locale objectForKey: NSAMPMDesignation];

		      /*
		       * The time addition is handled below because this
		       * indicator only modifies the time on a 12hour clock.
		       */
		      if ([[amPMNames objectAtIndex: 1] isEqual:
			currAMPM] == YES)
			{
			  ampm = YES;
			}
		    }
		    break;

		  case 'S':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    sec = atoi(tmpStr);
		    had |= hads;
		    break;

		  case 'w':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 1);
		    dayOfWeek = atoi(tmpStr);
		    had |= hadw;
		    break;

		  case 'W': // Fall through
		    weekStartsMonday = 1;
		  case 'U':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 1);
		    julianWeeks = atoi(tmpStr);
		    break;

		    //	case 'x':
		    //	break;

		    //	case 'X':
		    //	break;

		  case 'y':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 2);
		    year = atoi(tmpStr);
		    if (year >= 70)
		      {
			year += 1900;
		      }
		    else
		      {
			year += 2000;
		      }
		    had |= hadY;
		    break;

		  case 'Y':
		    sourceIdx += getDigits(&source[sourceIdx], tmpStr, 4);
		    year = atoi(tmpStr);
		    had |= hadY;
		    break;

		  case 'z':
		    {
		      int	sign = 1;
		      int	zone;

		      if (source[sourceIdx] == '+')
			{
			  sourceIdx++;
			}
		      else if (source[sourceIdx] == '-')
			{
			  sign = -1;
			  sourceIdx++;
			}
		      sourceIdx += getDigits(&source[sourceIdx], tmpStr, 4);
		      zone = atoi(tmpStr) * sign;

		      if ((tz = [NSTimeZone timeZoneForSecondsFromGMT: 
			(zone / 100 * 60 + (zone % 100)) * 60]) == nil)
			{
			  tz = localTZ;
			}
		    }
		    break;

		  case 'Z':
		    for (tmpIdx = sourceIdx; tmpIdx < sourceLen; tmpIdx++)
		      {
			if (isalpha(source[tmpIdx]) || source[tmpIdx] == '-'
			  || source[tmpIdx] == '+')
			  {
			    tmpStr[tmpIdx - sourceIdx] = source[tmpIdx];
			  }
			else
			  {
			    break;
			  }
		      }
		    tmpStr[tmpIdx - sourceIdx] = '\0';
		    sourceIdx += tmpIdx - sourceIdx;
		    {
		      NSString	*z = [NSString stringWithCString: tmpStr];

		      tz = [NSTimeZone timeZoneWithName: z];
		      if (tz == nil)
			{
			  tz = [NSTimeZone timeZoneWithAbbreviation: z];
			}
		      if (tz == nil)
			{
			  tz = localTZ;
			}
		    }
		    break;

		  default:
		    [NSException raise: NSInvalidArgumentException
				format: @"Invalid NSCalendar date, "
			@"specifier %c not recognized in format %@",
			format[formatIdx], fmt];
		}
	    } 
	  formatIdx++;
	}
      RELEASE(fd);

      if (tz == nil)
	{
	  tz = localTZ;
	}

      if (twelveHrClock == YES)
	{
	  if (ampm == YES && hour != 12)
	    {
	      hour += 12;
	    }
	}

      if (julianWeeks != -1)
	{
	  NSTimeZone		*gmtZone;
	  NSCalendarDate	*d;
	  int			currDay;

	  gmtZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];

	  if ((had & (hadY|hadw)) != (hadY|hadw))
	    {
	      NSCalendarDate	*now = [NSCalendarDate  date];

	      [now setTimeZone: gmtZone];
	      if ((had | hadY) == 0)
		{
		  year = [now yearOfCommonEra];
		  had |= hadY;
		}
	      if ((had | hadw) == 0)
		{
		  dayOfWeek = [now dayOfWeek];
		  had |= hadw;
		}
	    }

	  d  = [NSCalendarDate dateWithYear: year
				      month: 1
					day: 1
				       hour: 0
				     minute: 0
				     second: 0
				   timeZone: gmtZone];
	  currDay = [d dayOfWeek];

	  /*
	   * The julian weeks are either sunday relative or monday relative
	   * but all of the day of week specifiers are sunday relative.
	   * This means that if no day of week specifier was used the week
	   * starts on monday.
	   */
	  if (dayOfWeek == -1)
	    {
	      if (weekStartsMonday)
		{
		  dayOfWeek = 1;
		}
	      else
		{
		  dayOfWeek = 0;
		}
	    }
	  day = dayOfWeek + (julianWeeks * 7 - (currDay - 1));
	  had |= hadD;
	}

      return [self initWithYear: year
			  month: month
			    day: day
			   hour: hour
			 minute: min
			 second: sec
		       timeZone: tz];
    }
}

/**
 * Returns an NSCalendarDate instance with the given year, month, day,
 * hour, minute, and second, using aTimeZone.<br />
 * The year includes the century (ie you can't just say '02' when you
 * mean '2002').<br />
 * The month is in the range 1 to 12,<br />
 * The day is in the range 1 to 31,<br />
 * The hour is in the range 0 to 23,<br />
 * The minute is in the range 0 to 59,<br />
 * The second is in the range 0 to 59.<br />
 * If aTimeZone is nil, the [NSTimeZone+localTimeZone] value is used.
 * <p>
 *   GNUstep checks the validity of the method arguments, and unless
 *   the base library was built with 'warn=no' it generates a warning
 *   for bad values.  It tries to use those bad values to generate a
 *   date anyway though, rather than failing (this also appears to be
 *   the behavior of MacOS-X).
 * </p>
 * The algorithm GNUstep uses to create the date is this ...<br />
 * <list>
 *   <item>
 *     Convert the broken out date values into a time interval since
 *     the reference date, as if those values represent a GMT date/time.
 *   </item>
 *   <item>
 *     Ask the time zone for the offset from GMT at the resulting date,
 *     and apply that offset to the time interval ... so get the value
 *     for the specified timezone.
 *   </item>
 *   <item>
 *     Ask the time zone for the offset from GMT at the new date ...
 *     in case the new date is in a different daylight savings time
 *     band from the original date.  If this offset differs from the
 *     previous one, apply the difference so that the result is
 *     corrected for daylight savings.  This is the final result used.
 *   </item>
 *   <item>
 *     After establishing the time interval we will use and completing
 *     initialisation, we ask the time zone for the offset from GMT again.
 *     If it is not the same as the last time, then the time specified by
 *     the broken out date does not really exist ... since it's in the
 *     period lost by the transition to daylight savings.  The resulting
 *     date is therefore not the date that was actually asked for, but is
 *     the best approximation we can do.  If the base library was not
 *     built with 'warn=no' then a warning message is logged for this
 *     condition.
 *   </item>
 * </list>
 */
- (id) initWithYear: (int)year
	      month: (unsigned int)month
	        day: (unsigned int)day
	       hour: (unsigned int)hour
	     minute: (unsigned int)minute
	     second: (unsigned int)second
	   timeZone: (NSTimeZone *)aTimeZone
{
  unsigned int		c;
  NSTimeInterval	s;
  NSTimeInterval	oldOffset;
  NSTimeInterval	newOffset;

  if (month < 1 || month > 12)
    {
      NSWarnMLog(@"invalid month given - %u", month);
    }
  c = lastDayOfGregorianMonth(month, year);
  if (day < 1 || day > c)
    {
      NSWarnMLog(@"invalid day given - %u", day);
    }
  if (hour > 23)
    {
      NSWarnMLog(@"invalid hour given - %u", hour);
    }
  if (minute > 59)
    {
      NSWarnMLog(@"invalid minute given - %u", minute);
    }
  if (second > 59)
    {
      NSWarnMLog(@"invalid second given - %u", second);
    }

  // Calculate date as GMT
  s = GSTime(day, month, year, hour, minute, second, 0);

  // Assign time zone detail
  if (aTimeZone == nil)
    {
      _time_zone = localTZ;	// retain is a no-op for the local timezone.
    }
  else
    {
      _time_zone = RETAIN(aTimeZone);
    }
  _calendar_format = cformat;
  _seconds_since_ref = s;

  /*
   * Adjust date so it is correct for time zone.
   */
  oldOffset = offset(_time_zone, self);
  s -= oldOffset;
  _seconds_since_ref = s;

  /*
   * See if we need to adjust for daylight savings time
   */
  newOffset = offset(_time_zone, self);
  if (oldOffset != newOffset)
    {
      s -= (newOffset - oldOffset);
      _seconds_since_ref = s;
      oldOffset = offset(_time_zone, self);
      /*
       * If the adjustment puts us in another offset, we must be in the
       * non-existent period at the start of daylight savings time.
       */
      if (oldOffset != newOffset)
	{
	  NSWarnMLog(@"init non-existent time at start of daylight savings");
	}
    }

  return self;
}

/**
 * Initialises the receiver with the specified interval since the
 * reference date.  Uses th standard format string "%Y-%m-%d %H:%M:%S %z"
 * and the default time zone.
 */
- (id) initWithTimeIntervalSinceReferenceDate: (NSTimeInterval)seconds
{
  _seconds_since_ref = seconds;
  if (_calendar_format == nil)
    {
      _calendar_format = cformat;
    }
  if (_time_zone == nil)
    {
      _time_zone = localTZ;	// retain is a no-op for the local timezone.
    }
  return self;
}

/**
 * Return the day number (ie number of days since the start of) in the
 * 'common' era of the receiving date.  The era starts at 1 A.D.
 */
- (int) dayOfCommonEra
{
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  return dayOfCommonEra(when);
}

/**
 * Return the month (1 to 31) of the receiving date.
 */
- (int) dayOfMonth
{
  int m, d, y;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  gregorianDateFromAbsolute(dayOfCommonEra(when), &d, &m, &y);

  return d;
}

/**
 * Return the day of the week (0 to 6) of the receiving date.
 * <list>
 *   <item>0 is sunday</item>
 *   <item>1 is monday</item>
 *   <item>2 is tuesday</item>
 *   <item>3 is wednesday</item>
 *   <item>4 is thursday</item>
 *   <item>5 is friday</item>
 *   <item>6 is saturday</item>
 * </list>
 */
- (int) dayOfWeek
{
  int	d;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  d = dayOfCommonEra(when);

  /* The era started on a sunday.
     Did we always have a seven day week?
     Did we lose week days changing from Julian to Gregorian?
     AFAIK seven days a week is ok for all reasonable dates.  */
  d = d % 7;
  if (d < 0)
    d += 7;
  return d;
}

/**
 * Return the day of the year (1 to 366) of the receiving date.
 */
- (int) dayOfYear
{
  int m, d, y, days, i;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  gregorianDateFromAbsolute(dayOfCommonEra(when), &d, &m, &y);
  days = d;
  for (i = m - 1;  i > 0; i--) // days in prior months this year
    days = days + lastDayOfGregorianMonth(i, y);

  return days;
}

/**
 * Return the hour of the day (0 to 23) of the receiving date.
 */
- (int) hourOfDay
{
  int h;
  double a, d;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  d = dayOfCommonEra(when);
  d -= GREGORIAN_REFERENCE;
  d *= 86400;
  a = abs(d - (_seconds_since_ref + offset(_time_zone, self)));
  a = a / 3600;
  h = (int)a;

  // There is a small chance of getting
  // it right at the stroke of midnight
  if (h == 24)
    h = 0;

  return h;
}

/**
 * Return the minute of the hour (0 to 59) of the receiving date.
 */
- (int) minuteOfHour
{
  int h, m;
  double a, b, d;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  d = dayOfCommonEra(when);
  d -= GREGORIAN_REFERENCE;
  d *= 86400;
  a = abs(d - (_seconds_since_ref + offset(_time_zone, self)));
  b = a / 3600;
  h = (int)b;
  h = h * 3600;
  b = a - h;
  b = b / 60;
  m = (int)b;

  return m;
}

/**
 * Return the month of the year (1 to 12) of the receiving date.
 */
- (int) monthOfYear
{
  int m, d, y;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  gregorianDateFromAbsolute(dayOfCommonEra(when), &d, &m, &y);

  return m;
}

/**
 * Return the second of the minute (0 to 59) of the receiving date.
 */
- (int) secondOfMinute
{
  int h, m, s;
  double a, b, c, d;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  d = dayOfCommonEra(when);
  d -= GREGORIAN_REFERENCE;
  d *= 86400;
  a = abs(d - (_seconds_since_ref + offset(_time_zone, self)));
  b = a / 3600;
  h = (int)b;
  h = h * 3600;
  b = a - h;
  b = b / 60;
  m = (int)b;
  m = m * 60;
  c = a - h - m;
  s = (int)c;

  return s;
}

/**
 * Return the year of the 'common' era of the receiving date.
 * The era starts at 1 A.D.
 */
- (int) yearOfCommonEra
{
  int m, d, y;
  NSTimeInterval	when;

  when = _seconds_since_ref + offset(_time_zone, self);
  gregorianDateFromAbsolute(dayOfCommonEra(when), &d, &m, &y);

  return y;
}

/**
 * This method exists solely for conformance to the OpenStep spec.
 * Its use is deprecated ... it simply calls
 * -dateByAddingYears:months:days:hours:minutes:seconds:
 */
- (NSCalendarDate*) addYear: (int)year
		      month: (int)month
			day: (int)day
		       hour: (int)hour
		     minute: (int)minute
		     second: (int)second
{
  return [self dateByAddingYears: year
		          months: month
			    days: day
			   hours: hour
		         minutes: minute
		         seconds: second];
}

/**
 * Calls -descriptionWithCalendarFormat:locale: passing the receviers
 * calendar format and a nil locale.
 */
- (NSString*) description
{
  return [self descriptionWithCalendarFormat: _calendar_format locale: nil];
}

/**
 * Returns a string representation of the receiver using the specified
 * format string.<br />
 * Calls -descriptionWithCalendarFormat:locale: with a nil locale.
 */
- (NSString*) descriptionWithCalendarFormat: (NSString *)format
{
  return [self descriptionWithCalendarFormat: format locale: nil];
}

#define UNIX_REFERENCE_INTERVAL -978307200.0
/**
 * Returns a string representation of the receiver using the specified
 * format string and locale dictionary.<br />
 * Format specifiers are -
 * <list>
 *   <item>
 *     %a   abbreviated weekday name according to locale
 *   </item>
 *   <item>
 *     %A   full weekday name according to locale
 *   </item>
 *   <item>
 *     %b   abbreviated month name according to locale
 *   </item>
 *   <item>
 *     %B   full month name according to locale
 *   </item>
 *   <item>
 *     %d   day of month as decimal number (leading zero)
 *   </item>
 *   <item>
 *     %e   day of month as decimal number (leading space)
 *   </item>
 *   <item>
 *     %F   milliseconds (000 to 999)
 *   </item>
 *   <item>
 *     %H   hour as a decimal number using 24-hour clock
 *   </item>
 *   <item>
 *     %I   hour as a decimal number using 12-hour clock
 *   </item>
 *   <item>
 *     %j   day of year as a decimal number
 *   </item>
 *   <item>
 *     %m   month as decimal number
 *   </item>
 *   <item>
 *     %M   minute as decimal number
 *   </item>
 *   <item>
 *     %p   'am' or 'pm'
 *   </item>
 *   <item>
 *     %S   second as decimal number
 *   </item>
 *   <item>
 *     %U   week of the current year as decimal number (Sunday first day)
 *   </item>
 *   <item>
 *     %W   week of the current year as decimal number (Monday first day)
 *   </item>
 *   <item>
 *     %w   day of the week as decimal number (Sunday = 0)
 *   </item>
 *   <item>
 *     %y   year as a decimal number without century
 *   </item>
 *   <item>
 *     %Y   year as a decimal number with century
 *   </item>
 *   <item>
 *     %z   time zone offset (HHMM)
 *   </item>
 *   <item>
 *     %Z   time zone
 *   </item>
 *   <item>
 *     %%   literal % character
 *   </item>
 * </list>
 */
- (NSString*) descriptionWithCalendarFormat: (NSString*)format
				     locale: (NSDictionary*)locale
{
  char buf[1024];
  const char *f;
  int lf;
  BOOL mtag = NO, dtag = NO, ycent = NO;
  BOOL mname = NO, dname = NO;
  double s;
  int yd = 0, md = 0, mnd = 0, sd = 0, dom = -1, dow = -1, doy = -1;
  int hd = 0, nhd, mil;
  int i, j, k, z;

  if (locale == nil)
    locale = GSUserDefaultsDictionaryRepresentation();
  if (format == nil)
    format = [locale objectForKey: NSTimeDateFormatString];

  // If the format is nil then return an empty string
  if (!format)
    return @"";

  f = [format cString];
  lf = strlen(f);

  GSBreakTime(_seconds_since_ref + offset(_time_zone, self),
    &yd, &md, &dom, &hd, &mnd, &sd, &mil);
  nhd = hd;

  // Find the order of date elements
  // and translate format string into printf ready string
  j = 0;
  for (i = 0;i < lf; ++i)
    {
      // Only care about a format specifier
      if (f[i] == '%')
	{
	  // check the character that comes after
	  switch (f[i+1])
	    {
	      // literal %
	    case '%':
	      ++i;
	      buf[j] = f[i];
	      ++j;
	      break;

	      // is it the year
	    case 'Y':
	      ycent = YES;
	    case 'y':
	      ++i;
	      if (ycent)
		k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%04d", yd));
	      else
		k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", yd % 100));
	      j += k;
	      break;

	      // is it the month
	    case 'b':
	      mname = YES;
	    case 'B':
	      mtag = YES;    // Month is character string
	    case 'm':
	      ++i;
	      if (mtag)
		{
		  NSArray	*months;
		  NSString	*name;

		  if (mname)
		    months = [locale objectForKey: NSShortMonthNameArray];
		  else
		    months = [locale objectForKey: NSMonthNameArray];
		  name = [months objectAtIndex: md-1];
		  if (name)
		    k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%s",
		      [name cString]));
		  else
		    k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", md));
		}
	      else
		k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", md));
	      j += k;
	      break;

	    case 'd': 	// day of month
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", dom));
	      j += k;
	      break;

	    case 'e': 	// day of month
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%2d", dom));
	      j += k;
	      break;

	    case 'F': 	// milliseconds
	      s = ([self dayOfCommonEra] - GREGORIAN_REFERENCE) * 86400.0;
	      s -= (_seconds_since_ref + offset(_time_zone, self));
	      s = fabs(s);
	      s -= floor(s);
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%03d", (int)(s*1000)));
	      j += k;
	      break;

	    case 'j': 	// day of year
	      if (doy < 0) doy = [self dayOfYear];
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", doy));
	      j += k;
	      break;

	      // is it the week-day
	    case 'a':
	      dname = YES;
	    case 'A':
	      dtag = YES;   // Day is character string
	    case 'w':
	      {
		++i;
		if (dow < 0) dow = [self dayOfWeek];
		if (dtag)
		  {
		    NSArray	*days;
		    NSString	*name;

		    if (dname)
		      days = [locale objectForKey: NSShortWeekDayNameArray];
		    else
		      days = [locale objectForKey: NSWeekDayNameArray];
		    name = [days objectAtIndex: dow];
		    if (name)
		      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%s",
			[name cString]));
		    else
		      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%01d", dow));
		  }
		else
		  k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%01d", dow));
		j += k;
	      }
	      break;

	      // is it the hour
	    case 'I':
	      nhd = hd % 12;  // 12 hour clock
	      if (hd == 12)
		nhd = 12;     // 12pm not 0pm
	    case 'H':
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", nhd));
	      j += k;
	      break;

	      // is it the minute
	    case 'M':
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", mnd));
	      j += k;
	      break;

	      // is it the second
	    case 'S':
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%02d", sd));
	      j += k;
	      break;

	      // Is it the am/pm indicator
	    case 'p':
	      {
		NSArray		*a = [locale objectForKey: NSAMPMDesignation];
		NSString	*ampm;

		++i;
		if (hd >= 12)
		  {
		    if ([a count] > 1)
		      ampm = [a objectAtIndex: 1];
		    else
		      ampm = @"pm";
		  }
		else
		  {
		    if ([a count] > 0)
		      ampm = [a objectAtIndex: 0];
		    else
		      ampm = @"am";
		  }
		k = VSPRINTF_LENGTH(sprintf(&(buf[j]), [ampm cString]));
		j += k;
	      }
	      break;

	      // is it the zone name
	    case 'Z':
	      ++i;
	      k = VSPRINTF_LENGTH(sprintf(&(buf[j]), "%s",
		[abbrev(_time_zone, self) UTF8String]));
	      j += k;
	      break;

	    case 'z':
	      ++i;
	      z = offset(_time_zone, self);
	      if (z < 0) {
		z = -z;
		z /= 60;
	        k = VSPRINTF_LENGTH(sprintf(&(buf[j]),"-%02d%02d",z/60,z%60));
	      }
	      else {
		z /= 60;
	        k = VSPRINTF_LENGTH(sprintf(&(buf[j]),"+%02d%02d",z/60,z%60));
              }
	      j += k;
	      break;

	      // Anything else is unknown so just copy
	    default:
	      buf[j] = f[i];
	      ++i;
	      ++j;
	      buf[j] = f[i];
	      ++i;
	      ++j;
	      break;
	    }
	}
      else
	{
	  buf[j] = f[i];
	  ++j;
	}
    }
  buf[j] = '\0';

  return [NSString stringWithCString: buf];
}

- (id) copyWithZone: (NSZone*)zone
{
  NSCalendarDate	*newDate;

  if (NSShouldRetainWithZone(self, zone))
    {
      newDate = RETAIN(self);
    }
  else
    {
      newDate = (NSCalendarDate*)NSCopyObject(self, 0, zone);

      if (newDate != nil)
	{
	  if (_calendar_format != cformat)
	    {
	      newDate->_calendar_format = [_calendar_format copyWithZone: zone];
	    }
	  if (_time_zone != localTZ)
	    {
	      newDate->_time_zone = RETAIN(_time_zone);
	    }
	}
    }
  return newDate;
}

/**
 * Returns a description of the receiver using its normal format but with
 * the specified locale dictionary.<br />
 * Calls -descriptionWithCalendarFormat:locale: to do this.
 */
- (NSString*) descriptionWithLocale: (NSDictionary *)locale
{
  return [self descriptionWithCalendarFormat: _calendar_format locale: locale];
}

/**
 * Returns the format string associated with the receiver.<br />
 * See -descriptionWithCalendarFormat:locale: for details.
 */
- (NSString*) calendarFormat
{
  return _calendar_format;
}

/**
 * Sets the format string associated with the receiver.<br />
 * See -descriptionWithCalendarFormat:locale: for details.
 */
- (void) setCalendarFormat: (NSString *)format
{
  RELEASE(_calendar_format);
  _calendar_format = [format copyWithZone: [self zone]];
}

/**
 * Sets the time zone associated with the receiver.
 */
- (void) setTimeZone: (NSTimeZone *)aTimeZone
{
  ASSIGN(_time_zone, aTimeZone);
}

/**
 * Returns the time zone associated with the receiver.
 */
- (NSTimeZone*) timeZone
{
  return _time_zone;
}

/**
 * Returns the time zone detail associated with the receiver.
 */
- (NSTimeZoneDetail*) timeZoneDetail
{
  NSTimeZoneDetail	*detail = [_time_zone timeZoneDetailForDate: self];
  return detail;
}

@end

/**
 * Routines for manipulating Gregorian dates
 */
// The following code is based upon the source code in
// ``Calendrical Calculations'' by Nachum Dershowitz and Edward M. Reingold,
// Software---Practice & Experience, vol. 20, no. 9 (September, 1990),
// pp. 899--928.

@implementation NSCalendarDate (GregorianDate)

/**
 * Returns the number of the last day of the month in the specified year.
 */
- (int) lastDayOfGregorianMonth: (int)month year: (int)year
{
  return lastDayOfGregorianMonth(month, year);
}

/**
 * Returns the number of days since the start of the era for the specified
 * day, month, and year.
 */
- (int) absoluteGregorianDay: (int)day month: (int)month year: (int)year
{
  return absoluteGregorianDay(day, month, year);
}

/**
 * Given a day number since the start of the era, returns the dat as a
 * day, month, and year.
 */
- (void) gregorianDateFromAbsolute: (int)d
			       day: (int *)day
			     month: (int *)month
			      year: (int *)year
{
  // Search forward year by year from approximate year
  *year = d/366;
  while (d >= absoluteGregorianDay(1, 1, (*year)+1))
    (*year)++;
  // Search forward month by month from January
  (*month) = 1;
  while (d > absoluteGregorianDay(lastDayOfGregorianMonth(*month, *year),
    *month, *year))
    (*month)++;
  *day = d - absoluteGregorianDay(1, *month, *year) + 1;
}

@end


/**
 * Methods present in OpenStep but later removed from MacOS-X
 */
@implementation NSCalendarDate (OPENSTEP)

/**
 * <p>Returns a calendar date formed by adding the specified offsets to the
 * receiver.  The offsets are added in order, years, then months, then
 * days, then hours then minutes then seconds, so if you add 1 month and
 * forty days to 20th September, the result will be 9th November.
 * </p>
 * <p>This method understands leap years and tries to adjust for daylight
 * savings time changes so that it preserves expected clock time.
 * </p>
 */
- (NSCalendarDate*) dateByAddingYears: (int)years
			       months: (int)months
				 days: (int)days
			        hours: (int)hours
			      minutes: (int)minutes
			      seconds: (int)seconds
{
  NSCalendarDate	*c;
  NSTimeInterval	s;
  NSTimeInterval	oldOffset;
  NSTimeInterval	newOffset;
  int			i, year, month, day, hour, minute, second, mil;

  oldOffset = offset(_time_zone, self);
  /*
   * Break into components in GMT time zone.
   */
  GSBreakTime(_seconds_since_ref, &year, &month, &day, &hour, &minute,
    &second, &mil);

  while (years != 0 || months != 0 || days != 0
    || hours != 0 || minutes != 0 || seconds != 0)
    {
      year += years;
      years = 0;

      month += months;
      months = 0;
      while (month > 12)
	{
	  year++;
	  month -= 12;
	}
      while (month < 1)
	{
	  year--;
	  month += 12;
	}

      day += days;
      days = 0;
      if (day > 28)
	{
	  i = lastDayOfGregorianMonth(month, year);
	  while (day > i)
	    {
	      day -= i;
	      if (month < 12)
		{
		  month++;
		}
	      else
		{
		  month = 1;
		  year++;
		}
	      i = lastDayOfGregorianMonth(month, year);
	    }
	}
      else
	{
	  while (day < 1)
	    {
	      if (month == 1)
		{
		  year--;
		  month = 12;
		}
	      else
		{
		  month--;
		}
	      day += lastDayOfGregorianMonth(month, year);
	    }
	}

      hour += hours;
      hours = 0;
      days += hour/24;
      hour %= 24;
      if (hour < 0)
	{
	  days--;
	  hour += 24;
	}

      minute += minutes;
      minutes = 0;
      hours += minute/60;
      minute %= 60;
      if (minute < 0)
	{
	  hours++;
	  minute += 60;
	}

      second += seconds;
      seconds = 0;
      minutes += second/60;
      second %= 60;
      if (second < 0)
	{
	  minutes--;
	  second += 60;
	}
    }

  /*
   * Reassemble in GMT time zone.
   */
  s = GSTime(day, month, year, hour, minute, second, mil);
  c = [NSCalendarDate alloc];
  c->_calendar_format = cformat;
  c->_time_zone = RETAIN([self timeZone]);
  c->_seconds_since_ref = s;

  /*
   * Adjust date to try to maintain the time of day over
   * a daylight savings time boundary if necessary.
   */
  newOffset = offset(_time_zone, c);
  if (newOffset != oldOffset)
    {
      NSTimeInterval	tmpOffset = newOffset;

      s -= (newOffset - oldOffset);
      c->_seconds_since_ref = s;
      /*
       * If the date we have lies within a missing hour at a
       * daylight savings time transition, we use the original
       * date rather than the adjusted one.
       */
      newOffset = offset(_time_zone, c);
      if (newOffset == oldOffset)
	{
	  s += (tmpOffset - oldOffset);
	  c->_seconds_since_ref = s;
	}
    }
  return AUTORELEASE(c);
}

/**
 * Returns the number of years, months, days, hours, minutes, and seconds
 * between the receiver and the given date.
 */
- (void) years: (int*)years
	months: (int*)months
          days: (int*)days
         hours: (int*)hours
       minutes: (int*)minutes
       seconds: (int*)seconds
     sinceDate: (NSDate*)date
{
  NSCalendarDate	*start;
  NSCalendarDate	*end;
  NSCalendarDate	*tmp;
  int			diff;
  int			extra;
  int			sign;
  int			mil;
  int			syear, smonth, sday, shour, sminute, ssecond;
  int			eyear, emonth, eday, ehour, eminute, esecond;

  /* FIXME What if the two dates are in different time zones?
    How about daylight savings time?
   */
  if ([date isKindOfClass: [NSCalendarDate class]])
    tmp = (NSCalendarDate*)RETAIN(date);
  else if ([date isKindOfClass: [NSDate class]])
    tmp = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:
		[date timeIntervalSinceReferenceDate]];
  else
    [NSException raise: NSInvalidArgumentException
      format: @"%@ invalid date given - %@", NSStringFromSelector(_cmd), date];

  end = (NSCalendarDate*)[self laterDate: tmp];
  if (end == self)
    {
      start = tmp;
      sign = 1;
    }
  else
    {
      start = self;
      sign = -1;
    }

  GSBreakTime(start->_seconds_since_ref + offset(start->_time_zone, start),
    &syear, &smonth, &sday, &shour, &sminute, &ssecond, &mil);

  GSBreakTime(end->_seconds_since_ref + offset(end->_time_zone, end),
    &eyear, &emonth, &eday, &ehour, &eminute, &esecond, &mil);

  /* Calculate year difference and leave any remaining months in 'extra' */
  diff = eyear - syear;
  extra = 0;
  if (emonth < smonth)
    {
      diff--;
      extra += 12;
    }
  if (years)
    *years = sign*diff;
  else
    extra += diff*12;

  /* Calculate month difference and leave any remaining days in 'extra' */
  diff = emonth - smonth + extra;
  extra = 0;
  if (eday < sday)
    {
      diff--;
      extra = [end lastDayOfGregorianMonth: smonth year: syear];
    }
  if (months)
    *months = sign*diff;
  else
    {
      while (diff--)
	{
	  int tmpmonth = emonth - diff - 1;
	  int tmpyear = eyear;

          while (tmpmonth < 1)
	    {
	      tmpmonth += 12;
	      tmpyear--;
	    }
          extra += lastDayOfGregorianMonth(tmpmonth, tmpyear);
        }
    }

  /* Calculate day difference and leave any remaining hours in 'extra' */
  diff = eday - sday + extra;
  extra = 0;
  if (ehour < shour)
    {
      diff--;
      extra = 24;
    }
  if (days)
    *days = sign*diff;
  else
    extra += diff*24;

  /* Calculate hour difference and leave any remaining minutes in 'extra' */
  diff = ehour - shour + extra;
  extra = 0;
  if (eminute < sminute)
    {
      diff--;
      extra = 60;
    }
  if (hours)
    *hours = sign*diff;
  else
    extra += diff*60;

  /* Calculate minute difference and leave any remaining seconds in 'extra' */
  diff = eminute - sminute + extra;
  extra = 0;
  if (esecond < ssecond)
    {
      diff--;
      extra = 60;
    }
  if (minutes)
    *minutes = sign*diff;
  else
    extra += diff*60;

  diff = esecond - ssecond + extra;
  if (seconds)
    *seconds = sign*diff;

  RELEASE(tmp);
}

@end
