/** All of the external data
   Copyright (C) 1997 Free Software Foundation, Inc.
   
   Written by:  Scott Christley <scottc@net-community.com>
   Date: August 1997
   
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

#include "config.h"
#include "Foundation/NSString.h"


#include "Foundation/NSArray.h"
#include "Foundation/NSException.h"

/* Global lock to be used by classes when operating on any global
   data that invoke other methods which also access global; thus,
   creating the potential for deadlock. */
@class	NSRecursiveLock;
NSRecursiveLock *gnustep_global_lock = nil;

/*
 * Connection Notification Strings.
 */
NSString *NSConnectionDidDieNotification;

NSString *NSConnectionDidInitializeNotification;


/*
 * NSThread Notifications
 */
NSString *NSWillBecomeMultiThreadedNotification;

NSString *NSThreadDidStartNotification;

NSString *NSThreadWillExitNotification;


/*
 * Port Notifications
 */
NSString *PortBecameInvalidNotification;

NSString *InPortClientBecameInvalidNotification;

NSString *InPortAcceptedClientNotification;


NSString *NSPortDidBecomeInvalidNotification;



/* RunLoop modes */
NSString *NSConnectionReplyMode;



/* Exception handler */
NSUncaughtExceptionHandler *_NSUncaughtExceptionHandler;

/* NSBundle */
NSString *NSBundleDidLoadNotification;

NSString *NSShowNonLocalizedStrings;

NSString *NSLoadedClasses;


/* Stream */
NSString *StreamException;



/* Standard domains */
NSString *NSArgumentDomain;

NSString *NSGlobalDomain;

NSString *NSRegistrationDomain;


/* Public notification */
NSString *NSUserDefaultsDidChangeNotification;


/* Keys for language-dependent information */
NSString *NSWeekDayNameArray;

NSString *NSShortWeekDayNameArray;

NSString *NSMonthNameArray;

NSString *NSShortMonthNameArray;

NSString *NSTimeFormatString;

NSString *NSDateFormatString;

NSString *NSShortDateFormatString;

NSString *NSTimeDateFormatString;

NSString *NSShortTimeDateFormatString;

NSString *NSCurrencySymbol;

NSString *NSDecimalSeparator;

NSString *NSThousandsSeparator;

NSString *NSInternationalCurrencyString;

NSString *NSCurrencyString;

NSString *NSNegativeCurrencyFormatString;

NSString *NSPositiveCurrencyFormatString;

NSString *NSDecimalDigits;

NSString *NSAMPMDesignation;


NSString *NSHourNameDesignations;

NSString *NSYearMonthWeekDesignations;

NSString *NSEarlierTimeDesignations;

NSString *NSLaterTimeDesignations;

NSString *NSThisDayDesignations;

NSString *NSNextDayDesignations;

NSString *NSNextNextDayDesignations;

NSString *NSPriorDayDesignations;

NSString *NSDateTimeOrdering;


/* These are in OPENSTEP 4.2 */
NSString *NSLanguageCode;

NSString *NSLanguageName;

NSString *NSFormalName;

/* For GNUstep */
NSString *NSLocale;


/*
 * Keys for the NSDictionary returned by [NSConnection -statistics]
 */
/* These in OPENSTEP 4.2 */
NSString *NSConnectionRepliesReceived;

NSString *NSConnectionRepliesSent;

NSString *NSConnectionRequestsReceived;

NSString *NSConnectionRequestsSent;

/* These Are GNUstep extras */
NSString *NSConnectionLocalCount;

NSString *NSConnectionProxyCount;

/* Class description notification */
NSString *NSClassDescriptionNeededForClassNotification;


/*
 *	Setup function called when NSString is initialised.
 *	We make all the constant strings not be constant strings so they can
 *	cache their hash values and be used much more efficiently as keys in
 *	dictionaries etc.
 */
void
GSBuildStrings()
{
  static Class	SClass = 0;

  if (SClass == 0)
    {
      SClass = [NSString class];

      /*
       * Ensure that NSString is initialized ... because we are called
       * from [NSObject +initialize] which might be executing as a
       * result of a call to [NSString +initialize] !
       */
      [SClass initialize];

      InPortAcceptedClientNotification
	= [[SClass alloc] initWithCString:
	"InPortAcceptedClientNotification"];
      InPortClientBecameInvalidNotification
	= [[SClass alloc] initWithCString:
	"InPortClientBecameInvalidNotification"];
      NSAMPMDesignation
	= [[SClass alloc] initWithCString: "NSAMPMDesignation"];
      NSArgumentDomain
	= [[SClass alloc] initWithCString: "NSArgumentDomain"];
      NSBundleDidLoadNotification
	= [[SClass alloc] initWithCString: "NSBundleDidLoadNotification"];
      NSConnectionDidDieNotification
	= [[SClass alloc] initWithCString:
	"NSConnectionDidDieNotification"];
      NSConnectionDidInitializeNotification
	= [[SClass alloc] initWithCString:
	"NSConnectionDidInitializeNotification"];
      NSConnectionLocalCount
	= [[SClass alloc] initWithCString: "NSConnectionLocalCount"];
      NSConnectionProxyCount
	= [[SClass alloc] initWithCString: "NSConnectionProxyCount"];
      NSConnectionRepliesReceived
	= [[SClass alloc] initWithCString: "NSConnectionRepliesReceived"];
      NSConnectionRepliesSent
	= [[SClass alloc] initWithCString: "NSConnectionRepliesSent"];
      NSConnectionReplyMode
	= [[SClass alloc] initWithCString: "NSConnectionReplyMode"];
      NSConnectionRequestsReceived
	= [[SClass alloc] initWithCString: "NSConnectionRequestsReceived"];
      NSConnectionRequestsSent
	= [[SClass alloc] initWithCString: "NSConnectionRequestsSent"];
      NSCurrencyString
	= [[SClass alloc] initWithCString: "NSCurrencyString"];
      NSCurrencySymbol
	= [[SClass alloc] initWithCString: "NSCurrencySymbol"];
      NSDateFormatString
	= [[SClass alloc] initWithCString: "NSDateFormatString"];
      NSDateTimeOrdering
	= [[SClass alloc] initWithCString: "NSDateTimeOrdering"];
      NSDecimalDigits
	= [[SClass alloc] initWithCString: "NSDecimalDigits"];
      NSDecimalSeparator
	= [[SClass alloc] initWithCString: "NSDecimalSeparator"];
      NSEarlierTimeDesignations
	= [[SClass alloc] initWithCString: "NSEarlierTimeDesignations"];
      NSFormalName
        = [[SClass alloc] initWithCString: "NSFormalName"];
      NSGlobalDomain
	= [[SClass alloc] initWithCString: "NSGlobalDomain"];
      NSHourNameDesignations
	= [[SClass alloc] initWithCString: "NSHourNameDesignations"];
      NSInternationalCurrencyString
	= [[SClass alloc] initWithCString: "NSInternationalCurrencyString"];
      NSLanguageCode
        = [[SClass alloc] initWithCString: "NSLanguageCode"];
      NSLanguageName
        = [[SClass alloc] initWithCString: "NSLanguageName"];
      NSLaterTimeDesignations
	= [[SClass alloc] initWithCString: "NSLaterTimeDesignations"];
      NSLoadedClasses
	= [[SClass alloc] initWithCString: "NSLoadedClasses"];
      NSLocale
	= [[SClass alloc] initWithCString: "NSLocale"];
      NSMonthNameArray
	= [[SClass alloc] initWithCString: "NSMonthNameArray"];
      NSNegativeCurrencyFormatString
        = [[SClass alloc] initWithCString:
	"NSNegativeCurrencyFormatString"];
      NSNextDayDesignations
	= [[SClass alloc] initWithCString: "NSNextDayDesignations"];
      NSNextNextDayDesignations
	= [[SClass alloc] initWithCString: "NSNextNextDayDesignations"];
      NSPortDidBecomeInvalidNotification
	= [[SClass alloc] initWithCString:
	"NSPortDidBecomeInvalidNotification"];
      NSPositiveCurrencyFormatString
        = [[SClass alloc] initWithCString:
	"NSPositiveCurrencyFormatString"];
      NSPriorDayDesignations
	= [[SClass alloc] initWithCString: "NSPriorDayDesignations"];
      NSRegistrationDomain
	= [[SClass alloc] initWithCString: "NSRegistrationDomain"];
      NSShortDateFormatString
        = [[SClass alloc] initWithCString: "NSShortDateFormatString"];
      NSShortMonthNameArray
	= [[SClass alloc] initWithCString: "NSShortMonthNameArray"];
      NSShortTimeDateFormatString
	= [[SClass alloc] initWithCString: "NSShortTimeDateFormatString"];
      NSShortWeekDayNameArray
	= [[SClass alloc] initWithCString: "NSShortWeekDayNameArray"];
      NSShowNonLocalizedStrings
	= [[SClass alloc] initWithCString: "NSShowNonLocalizedStrings"];
      NSThisDayDesignations
	= [[SClass alloc] initWithCString: "NSThisDayDesignations"];
      NSThousandsSeparator
	= [[SClass alloc] initWithCString: "NSThousandsSeparator"];
      NSThreadDidStartNotification
	= [[SClass alloc] initWithCString: "NSThreadDidStartNotification"];
      NSThreadWillExitNotification
	= [[SClass alloc] initWithCString: "NSThreadWillExitNotification"];
      NSTimeDateFormatString
	= [[SClass alloc] initWithCString: "NSTimeDateFormatString"];
      NSTimeFormatString
	= [[SClass alloc] initWithCString: "NSTimeFormatString"];
      NSUserDefaultsDidChangeNotification
	= [[SClass alloc] initWithCString:
	"NSUserDefaultsDidChangeNotification"];
      NSWeekDayNameArray
	= [[SClass alloc] initWithCString: "NSWeekDayNameArray"];
      NSWillBecomeMultiThreadedNotification
	= [[SClass alloc] initWithCString:
	"NSWillBecomeMultiThreadedNotification"];
      NSYearMonthWeekDesignations
	= [[SClass alloc] initWithCString: "NSYearMonthWeekDesignations"];
      PortBecameInvalidNotification
	= [[SClass alloc] initWithCString: "PortBecameInvalidNotification"];
      StreamException
	= [[SClass alloc] initWithCString: "StreamException"];

      NSClassDescriptionNeededForClassNotification
        = [[SClass alloc] initWithCString:
	"NSClassDescriptionNeededForClassNotification"];
    }
}



/* For bug in gcc 3.1. See NSByteOrder.h */
void _gcc3_1_hack(void){}
