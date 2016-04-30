#!/usr/bin/perl
# -*- coding: utf-8 -*-

#HP TODO - will have to enable this at some point and deal with global variables
# $conditions, $today,$logspath, $ETPath, $wuData, $loc, $tzone & $key
#use strict;

#TODO
# File operations -- add error check and defaults if files don't exist
# 				  -- make sure I'm using the right today and yesterday filenames
# safefloat and safeint subs

use eto;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::XS;
use List::Util qw(min max sum);
use Data::Dumper;
use Time::Local;
use Date::Calc qw(Day_of_Year);
my $debug = 1;

my %config_parms = do 'config.pl';

#-[ Purpose ]------------------------------------------------------------------
#"""https://opensprinkler.com/forums/topic/penmen-monteith-eto-method-python-script-for-possible-use-as-weather-script/
#http://www.fao.org/docrep/x0490e/x0490e08.htm (Chapter 4 - Determination of ETo)
# (ET = evapotranspiration)
#
#I have included a quickly put together file using either the P-M ETo
#method or if enough data is not available the Hargreaves ETo method.
#
#The theory is that a user would create a program (1mm) of the number
#of seconds required to distribute 1mm of water in the coverage area
#(units: seconds/mm).  This would be saved as a program called 1mm.
#After doing this the user then inputs their WU api key just as they
#would for the Zimmerman method.  The script included would then read
#the current need or excess water from the logs stored on the uSD card
#and create a dynamic program with runtimes (run) utilizing the best
#averages for decorative grasses/drip systems, or a standard lawn grass
#used in the majority of the world.
#
#The script accounts for wind, freezing conditions, and current/recent
#rainfall when considering start and run times.  It will avoid watering
#during midday, unless early morning winds prevent earlier start times.
#The starts are serialized so no odd overlaps should occur.  Mornings
#are preferred to evenings to allow for the best use of water and
#absorption without causing mold and fungus growth by leaving grass wet
#overnight.  The script is commented quite heavily, so that anyone can
#edit or use it to their liking.  Please be mindful that other authors
#work was used or modified when the code seemed generalized enough that
#I shouldn’t be stepping on toes.  Please do not pester the original
#author if something doesn’t work for you, as they will probably have
#enough on their own plate with their own original works.
#
#If someone smarter than myself can find a way to hack this into the
#current Firmware for OS I would be extremely grateful as I’m sure
#quite a few others would be.  This script should comply with most
#watering restrictions in the US, however, I must say use at your own
#risk, I simply don’t have the time to puruse the near 600 pages of
#legal craziness for California alone.
#
#Everything is done based off your latitude and longitude, however, the
#script can find the info when provided with a city/state or country, a
#US Zip Code, or a PWS ID.

#=[ Notes ]======================================================================
#Directory structure
#.
#./weatherCustom.py              # (ro) main Python code
#./sitelibs                      #      Local python libraries (add to sys.path)
#./weatherprograms               #      Not programs in the OS sense
#./weatherprograms/1mm           # (ro) contains the # of sec required to distribute
#                                #      1mm (sec/mm) of water in the coverage area
#                                #      (1 for each station)
#                                #      {"mmTime":[15,16,20,10,30,30],"crop":[1,1,1,1,0,0]} JSON
#                                #      6 stations (I'm using 4 so my data will differ slightly)
#                                #      Crop is a 0 or 1 for grass or shrubs
#                                #      respecticvely. If a zone is primarily
#                                #      flowers 1 should be used for that zone.
#                                #      Primarily grass or low growing plants
#                                #      (less than about 4 inches high) should
#                                #      use 0. This will denote which ETo value
#                                #      to use.
#./weatherprograms/run           # (rw) runtime 
#                                #      [[ Sun Rise/set ], [ run min/zone ? ]]
#                                #      [[-1, -1, -1, -1], [0, 0, 0, 0, 0, 0]] //
#                                #      The -1 is the start times in minutes from
#                                #      midnight if a start time is needed.
#                                #      -1 means disabled
#./weatherprograms/minmax        # (ro) 
#                                #      [5,15] in mm?
#./ET                            # running totals for day to day [ grasses, shrubs ] in mm
#                                # each filename refers to the # of the day since Unix Epoch
#./ET/16775                      # (rw) final daily water balance for Epoch day 16775 (Yesterday)
#./ET/16776                      # (rw) final daily water balance for Epoch day 16776 (Today)
#./logs                          #
#./logs/16776                    # (rw) Epoch day 16776 log of [pid,x,runTime[x]] ... x is station, runTime is in seconds (yesterday)
#./logs/16776                    # (rw) Epoch day 16776 log of [pid,x,runTime[x]] ... x is station, runTime is in seconds (today_
#./wuData                        #
#./wuData/16776                  # (w)  Epoch day 16776 csv
#
#wuData/16776 csv format (tabbed):
#  observation_epoch
#  weather
#  temp_f
#  temp_c
#  relative_humidity
#  wind_degrees
#  wind_mph
#  wind_kph
#  precip_1hr_in
#  precip_1hr_metric
#  precip_today_string
#  precip_today_in
#  precip_today_metric
#  noWater

#"""
### @Todo: Well lots, I'm still trying to completely understand this (and I
###        don't).
###      : A lot of this data really needs to be in a db
###      : More error handling (I'm patching along the way and it shows)

###########################################################################################################
##                                   Credits                                                             ##
###########################################################################################################
## portions of code provided by Zimmerman method used by OpenSprinkler                                   ##
## portions of code provided/edited by Ray and Samer of OpenSprinkler                                    ##
## Compilation of this file and original code provided by Shawn Harte 2014 no copyright reserved         ##
## If you find use of your code unreasonable please contact shawn@veuphoria.com for removal or rewrite   ##
## please contact original authors with respect to their works, I can support only this effort           ##
## Code was used with utmost respect to the original authors, your efforts have prevented the            ##
## re-invention of the wheel, Thanks for your dedication to the OpenSprinkler project                    ##
###########################################################################################################

#
################################################################################
# -[ Functions ]----------------------------------------------------------------

# define safe functions for variable conversion, preventing errors with NaN and Null as string values
# 's'=value to convert 'dv'=value to default to on error make sure this is a legal float or integer value

#just stub for testing, have to fix up the floats and int
sub safe_float {
	my ($arg,$val) = @_;
#	$val = "0.0" unless ($val);
#	$arg = $val unless ($arg);
	return ($arg);
}

sub safe_int {
	my ($arg,$val) = @_;
#	$val = "0" unless ($val);
#	$arg = $val unless ($arg);	
	return ($arg);
}

sub isInt {
	my ($arg) = @_;
	return ($arg - int($arg))? 0 : 1;
}

sub isFloat {
	my ($arg) = @_;
	return 1;
	#return ($arg - int($arg))? 1 : 0;
}

sub round {
    my ($number, $places) = @_;
    my $sign = ($number < 0) ? '-' : '';
    my $abs = abs($number);

    if($places < 0) {
        $places *= -1;
        return $sign . substr($abs+("0." . "0" x $places . "5"),
                              0, $places+length(int($abs))+1);
    } else {
        my $p10 = 10**$places;
        return $sign . int($abs/$p10 + 0.5)*$p10;
    }
}


#def safe_float(s, dv=0.0):
#    try:
#        return float(s)
#    except:
#        return dv
#    #
##
#def safe_int(s, dv=0):
#    try:
#        return int(float(s))
#    except:
#        return dv
#    #
##
#def isInt(s):
#    try:
#        _v = int(s)
#    except:
#        return 0
#    #
#    return 1
#
#
#def isFloat(s):
#    try:
#        _f = float(s)
#    except:
#        return 0
#    #
#    return 1
##

#HP this might be vastly wrong, don't know why there are hardcoded values. For now just return none.
sub getTZoneOffset {
	my ($tz) = @_;
	
    if ($tz) {
		my @tnow = localtime(time);
		my $tdelta = timegm(@tnow) - timelocal(@tnow);     

        if ($tdelta) {
            return ({'t' => ($tdelta.seconds / 900 + 48), 'gmt' => ($tdelta / 3600)});
        } else {
            return ({'t' => "None", 'gmt' => "None"});
        }
    }
}
 
# Get all data for the location this should only be called once, several functions below will handle the data

sub getwuData {

    my $tloc = split(',', $loc);
    #return if ($key == '' or (scalar ($tloc) < 2));
#print "key=$key, loc=$loc\n";    
	my $ua = new LWP::UserAgent( keep_alive => 1 );

    my $request = HTTP::Request->new( GET => "http://api.wunderground.com/api/$key/astronomy/yesterday/conditions/forecast/q/$loc.json" );
#    my $request = HTTP::Request->new( GET => "http://192.168.0.50/$loc.json" );

    my $responseObj = $ua->request($request);
    my $data;
    eval { $data = JSON::XS->new->decode( $responseObj->content ); };
    my $responseCode = $responseObj->code;
    my $isSuccessResponse = $responseCode < 400;
    print "code=$responseCode\n";
    #print Dumper $data;
	my $offsets;
    # Last chance to get that timezone information
	if ($tzone eq "None" or $tzone eq "") {
		$offsets = getTZoneOffset($data->{current_observation}->{local_tz_long});
	} else {
		$offsets = getTZoneOffset($tzone);
	}
	
	return ($data, $offsets);
	
}

# Calculate an adjustment based on predicted rainfall
# Rain forecast should lessen current watering and reduce rain water runoff, making the best use of rain.
# returns tadjust (???)
sub getForecastData {
	my ($data) = @_;
#HP TODO - I don't know why the python wanted to create a bunch of arrays (mm, cor, wfc). It seems like
#HP TODO -  just the end result is needed
    if (@{$data}) {
#        nd = len(data)
#        mm = [0.0] * nd
#        cor = [0.0] * nd
#        wfc = [0.0] * nd
#        fadjust = [0.0] * nd
        my $fadjust = 0;
        for (my $day = 1; $day < scalar (@{$data}); $day++) {
            my $mm  = $data->[$day]->{qpf_allday}->{mm};
            my $cor = $data->[$day]->{pop};
            #my $cor = $fday->{pop};
            my $wfc = 1 / $day ** 2; #HP I assume this is to modify that further days out are more volatile?
            $fadjust += safe_float($mm,  -1) * (safe_float($cor, -1) / 100) * safe_float($wfc, -1);
#print "gf [$mm,$cor,$wfc,$fadjust]\n";
#print "gf2 [" . safe_float($mm,  -1) . ',' . (safe_float($cor, -1) / 100) . ',' . safe_float($wfc, -1) . "]\n";
#print "[" .safe_float($mm,  -1) . "," . (safe_float($cor, -1) / 100) . "," . safe_float($wfc, -1) ."]\n";
        }
#        except:
#            return -1
        #
        return $fadjust;
    }
    return -1;
}
    #
#

# Grab the sunrise and sunset times in minutes from midnight
sub getAstronomyData {
	my ($data) = @_;
	
    if (not $data) {
        return ({"rise" => -1, "set" => -1});
    }
    #

    my $rHour = safe_int($data->{'sunrise'}->{'hour'}, 6);
    my $rMin  = safe_int($data->{'sunrise'}->{'minute'});
    my $sHour = safe_int($data->{'sunset'}->{'hour'}, 18);
    my $sMin  = safe_int($data->{'sunset'}->{'minute'});
    ## sunrise = (rHour*60)+rMin
    ## sunset  = (sHour*60)+sMin
    if ($rHour, $rMin, $sHour, $sMin) {
        return ({"rise" => $rHour * 60 + $rMin, "set" => $sHour * 60 + $sMin});
    } else {
        return ({"rise" => -1, "set" => -1});
    }
}
    #
#

# Let's check the current weather and make sure the wind is calm enough, it's not raining, and the temp is above freezing
# We will also look at what the rest of the day is supposed to look like, we want to stop watering if it is going to rain,
# or if the temperature will drop below freezing, as it would be bad for the pipes to contain water in these conditions.
# Windspeed for the rest of the day is used to determine best low wind watering time.

sub getConditionsData {
	my ($current, $predicted) = @_;
	
    my $nowater = 1;
    my $whynot = 'Unknown';
    unless ($current and $predicted) {
        #eturn (cmm, nowater, whynot)
        return (0,   1, 'No conditions data');
    }
    #
    my $cWeather = safe_float($conditions->{$current->{weather}}, 5);
 #print "[$current->{weather}, " . $conditions->{$current->{weather}} . ", $conditions->{'Mostly Cloudy'}, $cWeather]\n";   

    unless ($cWeather) {
#HP I think this checks if $current{weather} is in the list in the hash
#HP TODO: what does the any(x in current['weather'].lower() for x in chkcond): mean???
		if (defined $conditions->{$current->{weather}} ) {
			$cWeather = 10;
		} else {
	    	print 'not found current ' . $current->{weather} . "\n";
			$cWeather = 5;
		}
	}
 
    my $cWind = &eto::wind_speed_2m(safe_float($current->{wind_kph}), 10);
    my $cTemp = safe_float($current->{temp_c}, 20);

    # current rain will only be used to adjust watering right before the start time

    my $cmm      = safe_float($current->{precip_today_metric});                 # Today's predicted rain (mm)
    my $pWind    = &eto::wind_speed_2m(safe_float($predicted->{avewind}->{kph}), 10); # Today's predicted wind (kph)
    my $pLowTemp = safe_float($predicted->{low}->{celsius});                    # Today's predicted low  (C)
    my $pCoR     = safe_float($predicted->{pop}) / 100;                       # Today's predicted POP  (%)  (Probability of Precipitation)
    my $pmm      = safe_float($predicted->{qpf_allday}->{mm});                  # Today's predicted QFP  (mm) (Quantitative Precipitation Forecast)
    #

    # Let's check to see if it's raining, windy, or freezing.  Since watering is based on yesterday's data
    # we will see how much it rained today and how much it might rain later today.  This should
    # help reduce excess watering, without stopping water when little rain is forecast.

    $nowater = 0;
    my $whynot = '';

        # Its precipitating
    if ($cWeather == 10 and lc $current->{weather} ne 'overcast') {
        $nowater = 1;
        $whynot .= 'precip (' . $current->{weather} . ') ';
    }
        #

        # Too windy
    if ($cWind > $pWind and $pWind > 6 or $cWind > 8 ) {
        $nowater = 1;
        $whynot .= 'wind (' . round($cWind, 2) . ' kph) ';
    }
        #

        # Too cold
    if ($cTemp < 4.5 or $pLowTemp < 1) {
        $nowater = 1;
        $whynot .= 'cold (' . round($cTemp, 2) . ' C) ';
    }
        #

    $cmm += $pmm * $pCoR if ($pCoR);    
        #
#HP TODO  - Don't know where this except comes from    
#HP    except:
#HP        print 'we had a problem and just decided to water anyway'
#HP        nowater = 0
    #
#print "[$cmm,$nowater,$whynot]\n";
    return ($cmm, $nowater, $whynot);
}
#

#
sub sun_block {
# Difference from Python script. If there are multiple forecasts for a given hour (ie overcast and scattered clouds), then it will
# take the last entry for calculating cover. Could average it, but really the difference isn't that huge I don't think.
	my ($sunrise, $sunset) = @_;
    my $sh = 0;
    my $previousCloudCover = 0;
    #print Dumper $wuData->{history}->{observations};
    #in range(sunrise / 60, sunset / 60 + 1):
#print Dumper @{$wuData->{history}->{observations}};
    for (my $hour = int($sunrise / 60); $hour < int($sunset / 60 + 1); $hour++) { 
        # Set a default value so we know we found missing data and can handle the gaps
        my $cloudCover = -1;

        # Now let's find the data for each hour there are more periods than hours so only grab the first
        #in range(len(wuData['history']['observations'])):
        for (my $period = 0; $period < scalar (@{$wuData->{history}->{observations}}); $period++) {
            if (safe_int($wuData->{history}->{observations}->[$period]->{date}->{hour}, -1) == $hour ) {
                if ($wuData->{history}->{observations}->[$period]->{conds}) {
                	print "[$hour," . $wuData->{history}->{observations}->[$period]->{conds} . "," . $conditions->{$wuData->{history}->{observations}->[$period]->{conds}} . "]\n";
                    $cloudCover = safe_float($conditions->{$wuData->{history}->{observations}->[$period]->{conds}}, 5) / 10;
                    unless (defined $cloudCover) {
                   		$cloudCover = 10;
                        print 'Condition not found ' . $wuData->{history}->{observations}->[$period]->{conds};
                    }
                }
            }
        }

        # Found nothing, let's assume it was the same as last hour
        $cloudCover = $previousCloudCover if ($cloudCover == -1);
print "[$hour,$cloudCover]\n";            
        #

        $previousCloudCover = $cloudCover;
        
        # Got something now? let's check
        $sh += 1 - $cloudCover if ($cloudCover != -1);
print "bob $sh $cloudCover\n";
            
        #
    }
    return ($sh);
}
#

# We need to know how much it rained yesterday and how much we watered versus how much we required
sub mmFromLogs {
	my ($_1mmProg) = @_;
#    """ Return mm from yesterday's log and yesterday's ET (??? what is tET)
#    Keyword arguments:
#    _1mmProg -- python list [] of json conversion of 1mm program
#    """

    # Was ydate, calling it prevLogFname now as we're to use the previous
    # (ASCII, numerical, file name), recent, log

	my $prevLogFname =  int((time - (time % 86400) -1) / 86400);
	$prevLogFname = $today - 1 if ($today);
	
    #
    my $nStations = scalar( @{$_1mmProg->{mmTime}} );

	my @ydur = (-1) x $nStations;
	my @ymm = (-1) x $nStations;    

    my @yET = (0,0); # Yesterday's Evap (evapotranspiration, moisture losses mm/day)
    my @tET = (0,0);

    # --------------------------------------------------------------------------
    ### Removing the confusion

    # I (ShawnHarte) have modified the script to search backwards for
    # the most recent ET file, it a will also create a base 0’d file
    # if the directory is empty. Currently I’m working on modifying
    # the OS firmware to work entirely off the SD card allowing for
    # more accurate programs, more programs, and better history from
    # which trends can be recognized and adjustments could be made. I
    # haven’t posted it to github yet because I don’t want to brick
    # anyone’s hardware. Currently it is a pseudo functional alpha
    # version. Another week or 2 and I should have a version worth
    # posting.

    # What he wants to do is iterate through to get the last previous
    # log file
    # I'd recommend attempt to open the yesterday's log file
    # -[ Logs ]-----------------------------------------------------------------
    my @logs = ();
	if (open (FILE, "$logsPath/$prevLogFname")) {
		my $d_logs = <FILE>;
		my $t_logs;
		eval { $t_logs = JSON::XS->new->decode($d_logs) };
		@logs = @$t_logs;
		close (FILE);
	} else {	
#TODO walk the directory to find the last file
		print "Can't open file $logsPath/$prevLogFname!\n";
		close (FILE);
	}

    # @TODO: get previous log file (not today's but the most recent previous log file)
    # Okay, I think here's what Shawn wanted to do:
    # open up the logs directory, get the last date.file and use that as the
    # reference. Yesterday is prefered but the might not be a yesterday log

    ### the original code first looked for yesterday's log file and used that
    ### filename to get the json from ETPath and LogsPath.
    ### I simply check for yesterday's files and if I get an exception I create
    ### default vaules of 0 (in the appropriate array format)
    ###

    # -[ ET ]-------------------------------------------------------------------
    # Last file? So ET/<Last_file>
	if (open (FILE, "$ETPath/$prevLogFname")) {
		my $d_yET = <FILE>;
		my $t_yET;
		eval { $t_yET = JSON::XS->new->decode($d_yET) };
		@yET = @$t_yET;		
		close (FILE);
	} else {	
#HPTODO walk the directory to find the last file
		print "Can't open file $ETPath/$prevLogFname!\n";
		close (FILE);
	}
	
#print "-----------------mmFromLogs-------------\n";
#print Dumper @{$t->{mmTime}};
#print "----------\n";
#print Dumper @yET;
#print "----------\n";
#print Dumper @logs;
#print "----------\n";
#print "[nStations=$nStations]\n";
#print "-----------------mmFromLogs-------------\n";
	
#    for x in logs:
#        if int(x[0]) == pid: # Not sure why this is here
#            ydur[safe_int(x[1])] += safe_int(x[2]) # Take yesterdays duration for station n x[1] and add the seconds (x[2])
        #
    #

#HP ydur is empty so why are we adding to it in python? Just set it to the log?

	for (my $x = 0; $x < $nStations; $x++) {
print "[logs[$x][2] = " . $logs[$x][2] . "]\n";
			$ydur[$x] += $logs[$x][2];
        } 

    ### @FIXME: Unknown issue at this time but the ymm is getting set to negative
    ###         values here

    for (my $x =0; $x < $nStations; $x++) {
        if ($_1mmProg->{mmTime}[$x]) {
            # 'mmTime': [15, 16, 20, 10, 30, 30] sec/mm
            # 'crop': [1, 1, 1, 1, 0, 0] 1 = grasses, 0 = shrubs
            #ymm[x] = round( (safe_float(yET[safe_int(_1mmProg['crop'][x])])) - (ydur[x]/safe_float(_1mmProg['mmTime'][x])), 4) * (-1)
            # Rewritten to make it readable (nothing more)
            my $yesterdaysET       = safe_float($yET[safe_int($_1mmProg->{crop}[$x])]); # in seconds
            my $yesterdaysDuration = $ydur[$x];                                        # in mm
            my $mmProg             = safe_float($_1mmProg->{mmTime}[$x]);              # in seconds/mm
            # ymm = yET - (ydur / mmTime)  // mm - (sec / sec/mm) Units look correct!
            $ymm[$x] = ($yesterdaysET - ($yesterdaysDuration/$mmProg) ) * (-1);
            $tET[int($_1mmProg->{crop}[$x])] = $ymm[$x];
print "[$x yesterdaysET = $yesterdaysET yesterdaysDuration = $yesterdaysDuration mmProg=$mmProg ymm[$x] = ". $ymm[$x] . " tET[" . int($_1mmProg->{crop}[$x]) . "] = " . $ymm[$x] ."]\n";

            print "E:   $x $ymm[$x] = ( " . $yET[$_1mmProg->{crop}[$x]] . " ) - ( $ydur[$x] / " . $_1mmProg->{mmTime}[$x] . " ) * -1\n";
            print "E:   $x _1mmProg['crop'][$x] = ". $_1mmProg->{crop}[$x] ."\n";
            print "E:   $x tET[" . int($_1mmProg->{crop}[$x]) . "] = " . $tET[int($_1mmProg->{crop}[$x])] . "\n";
            #
        } else {
            $ymm[$x] = 0;
        }
    }
        #
    #
    
    print  "E: Done - mmFromLogs\n";
    return (\@ymm, \@tET);
}

#sub XmmFromLogs {
#	my ($t) = @_;

# yesterday's date.	
#    ydate = (datetime.today() - datetime.utcfromtimestamp(0)).days - 1
#	my $ydate = (time - (time % 86400) -1) / 86400;

#HP TODO - I think this looks for previous file names?	
#    filenames = next(os.walk(logsPath))[2]
#    for x in filenames:
#        ldate = x
#        if ldate == str(ydate):
#            fpath = x
#        #
#    #
#	my $fpath = $ydate; 
#	open (FILE, "$ETPath/$fpath");
#	my $yET = <FILE>;
#	close (FILE);
#    tET = [0] * len(yET)
#	my @tET = ();
#	open (FILE, "$logsPath/$fpath");
#	my $logs = <FILE>;
#	close (FILE);
	
#    my $l = scalar (@{$t->{mmTime}});
#    my @ydur = [-1] x $l;
#	my @ymm = [-1] x $l;


#    for x in logs:
#        if int(x[0]) == pid:
#            ydur[safe_int(x[1])] += safe_int(x[2])
#        #
#    #
#    for x in range(l):
#        if t['mmTime'][x]:
#            ymm[x] = round(safe_float(yET[safe_int(t['crop'][x])]) - ydur[x] / safe_float(t['mmTime'][x]), 4) * -1
#            tET[int(t['crop'][x])] = ymm[x]
#        else:
#            ymm[x] = 0
#        #
#    #
#    return (@ymm, @tET);

#}
#
sub writeResults {
	my (@ET) = @_;

#HP TODO	

	my $data_1mm;
	if (open (FILE, "$WPPath/1mm")) {
		my $ddata_1mm = <FILE>;
		eval { $data_1mm = JSON::XS->new->decode($ddata_1mm) };
		close (FILE);
	} else {
		print "Problem opening $WPPath/1mm\n";
		close (FILE);
	}

	my @minmax;
	if (open (FILE, "$WPPath/minmax")) {
		my $dminmax = <FILE>;
		my $tmp_mm;
		eval { $tmp_mm = JSON::XS->new->decode($dminmax) };
		@minmax = @$tmp_mm;		#to get an array not an array ref		
		close (FILE);
	} else {
		print "Problem opening $WPPath/minmax\n";
		close (FILE);
		@minmax = (5, 15);
	}
	my $fname = int((time) / 86400);
	$fname = $today if ($today);
	
	my $minRunmm = 5;
	$minRunmm = min @minmax if (scalar (@minmax) > 0) and ((min @minmax) >= 0);
	my $maxRunmm = 15;
	$maxRunmm = max @minmax if (scalar (@minmax) > 1) and ((max @minmax) >= $minRunmm);
	my $times = 0;
	
#print "-----------------writeResults1-------------\n";
#print Dumper $t; #@{$t->{mmTime}};
#print "t--------\n";
#print Dumper $data_1mm;
#print "1mm--------\n";
#print Dumper @minmax;
#print "mm--------\n";
#print Dumper @ET;
#print "ET--------\n";
#print "[1mm=$data_1mm]\n";
#print "[minmax=$minmax]\n";
#print "[today fname=$fname]\n";
#print "[min=$minRunmm max= $maxRunmm len = " . scalar (@minmax) . "]\n";
#print "-----------------writeResults2-------------\n";
	
	my ($ymm, $yET) = mmFromLogs($data_1mm);
	
print "ymm = " . join(',',@$ymm) . "\n";
print "yET = " . join(',',@$yET) . "\n";	
#print "-----------------writeResults3-------------\n";
	
        my @tET = [0] x scalar (@ET);

        # @FIXME: I think this is where we go negative on the ET.
        # Not sure what a negative ET means but it's messing up the values.
#        for x in range(len(ET)):
#            if debug != 0:
#                print >>sys.stderr, "E:   ET[%s] = %s, yET[%s] = %s" % (x, ET[x], x, yET[x])
            #
    for (my $x = 0; $x < scalar (@ET); $x++) {
        print "[ET[$x] = $ET[$x] yET[$x] = @$yET[$x]]\n";
        $ET[$x] -= @$yET[$x];
    }
#print "-----------------writeResults4-------------\n";

#            ET[x] -= yET[x]
        #
		my @runTime = ();
        for (my $x = 0; $x < scalar (@{$data_1mm->{mmTime}}); $x++) {
            my $aET = safe_float($ET[$data_1mm->{crop}[$x]] - $todayRain - @$ymm[$x] - $tadjust); # tadjust is global ?
            my $pretimes = $times;
#HP TODO I'm not sure what this does?
            $times = int(max ( min( $aET / $maxRunmm, 4), $times)); # int(.999999) = 0
            print "E:   aET[$x] = $aET (" . $aET / $maxRunmm . ") // mm/Day\n";
            print "E:   times = $times (max " .max (min ( $aET / $maxRunmm,4),$times) . "/min " . min($aET/$maxRunmm,4) ." max(min(". $aET / $maxRunmm . ", 4), $pretimes))\n";
                #
            #
            # @FIXME: this is way too hard to read
            
#            runTime.append(min(max(safe_int(data['mmTime'][x] * ((aET if aET >= minRunmm else 0)) * (not noWater)), 0), \
#                                   safe_int(data['mmTime'][x]) * maxRunmm))
			my $tminrun = safe_int($data_1mm->{mmTime}[$x]);
			$tminrun = 0 unless $aET >= $minRunmm;
			$tminrun = int($tminrun * $aET);
			$tminrun = 0 if $noWater;
			my $tmaxrun = safe_int($data_1mm->{mmTime}[$x]) * $maxRunmm;
			print "E: HP mmTime = " . $data_1mm->{mmTime}[$x] . " tminrun=$tminrun tmaxrum=$tmaxrun\n";
			push (@runTime,  min ($tminrun, $tmaxrun));
		}
            #
        #

        # #########################################
        # # Real logs will be written already    ##
        # #########################################

    print "[" . scalar (@runTime) . "]\n";
	if (open (FILE, ">$logsPath/$fname")) {
		my $logData = "[";
		for (my $x = 0; $x < scalar (@runTime); $x++) {
			my $delim = "";
			$delim = ", " unless $x == 0; 
			$logData .= $delim . "[$pid, $x, " . $runTime[$x] . "]";
		}
		$logData .= "]";
		print FILE $logData;
		close (FILE);
	} else {	
		print "Can't open file $logsPath/$fname!\n";
		close (FILE);
	}


    my $stationID = $wuData->{current_observation}->{station_id};
	print 'Weather Station ID:  ' . $stationID . "\n"; 

#        except:
#            print 'Problem opening log file ' + logsPath + '/' + fname + ' - 1'
#        #

        # #########################################
        # # Write final daily water balance      ##
        # #########################################
	if (open (FILE, ">$ETPath/$fname")) {
		my $Data = "[";
		for (my $x = 0; $x < scalar (@ET); $x++) {
			my $delim = "";
			$delim = ", " unless $x == 0; 
			$Data .= $delim . $ET[$x];
		}
		$Data .= "]";
		print FILE $Data;
		close (FILE);
	} else {	
		print "Can't open file $ETPath/$fname!\n";
		close (FILE);
	}


        # ##########################################

        # This is really confusing, we're copying the possible run times into
        # availTimes (len 4) but then copying that into startTime (len times)
        # which seems to suggest that times can be something other than 4 but
        # if it's greater than 4 then we'll get an error
#HP - ok, this is explained by the opensprinker setup, a program can have up to 4 runtimes
#HP - useful to avoid grass saturation. So if really dry and needs lots of moisture, then run
#HP - multiple programs

    my @startTime  = (-1) x 4;
    my @availTimes = ( $sun->{rise} - sum( @runTime) / 60, 
                       $sun->{rise} + 60, 
                       $sun->{set} - sum( @runTime) / 60, 
                       $sun->{set} + 60 );
#        #
	print "[$times]\n";
#        for x in range(times):
#            startTime[x] = availTimes[x]
#        #

    my $runTime_str = "[[" . join(',',@startTime) . "],[" . join(',', @runTime) . "]]";
    print "Current logged ET [" . join(',', @ET) . "]\n";
    print "[" . join (',', @{$data_1mm->{mmTime}}) . "]\n";
#HP TODO clean this up
    print "$runTime_str\n";
	if (open (FILE, ">$WPPath/run")) {;
		print FILE $runTime_str;
		close (FILE);
	} else {	
		print "Can't open file $WPPath/run!\n";
		close (FILE);
	}        
        
}
# -[ Data ]---------------------------------------------------------------------

# Mapping of conditions to a level of shading.
# Since these are for sprinklers any hint of snow will be considered total cover (10)
# Don't worry about wet conditions like fog these are accounted for below we are only concerned with how much sunlight is blocked at ground level

	our $conditions = {
    	'Clear' => 0,
    	'Partial Fog' => 2,
    	'Patches of Fog' => 2,
    	'Haze' => 2,
    	'Shallow Fog' => 3,
    	'Scattered Clouds' => 4,
    	'Unknown' => 5,
    	'Fog' => 5,
    	'Partly Cloudy' => 5,
    	'Mostly Cloudy' => 8,
    	'Mist' => 10,
    	'Light Drizzle' => 10,
    	'Light Freezing Drizzle' => 10,
    	'Light Freezing Rain' => 10,
    	'Light Ice Pellets' => 10,
    	'Light Rain' => 10,
    	'Light Rain Showers' => 10,
    	'Light Snow' => 10,
    	'Light Snow Grains' => 10,
    	'Light Snow Showers' => 10,
    	'Light Thunderstorms and Rain' => 10,
    	'Low Drifting Snow' => 10,
    	'Rain' => 10,
    	'Rain Showers' => 10,
    	'Snow' => 10,
    	'Snow Showers' => 10,
    	'Thunderstorm' => 10,
    	'Thunderstorms and Rain' => 10,
    	'Blowing Snow' => 10,
    	'Chance of Snow' => 10,
    	'Freezing Rain' => 10,
    	'Unknown Precipitation' => 10,
    	'Overcast' => 10,
		};

# List of precipitation conditions we don't want to water in, the conditions will be checked to see if they contain these phrases.

	our $chkcond = {
    	'flurries',
    	'rain',
    	'sleet',
    	'snow',
    	'storm',
    	'hail',
    	'ice',
    	'squall',
    	'precip',
    	'funnel',
    	'drizzle',
    	'mist',
    	'freezing',
		};

#HP TODO - All this should be stored in a $config_parm
# -[ Init ]---------------------------------------------------------------------
    our $logsPath = $ARGV[1];
    $logsPath = 'logs' unless $logsPath;

    our $ETPath = $ARGV[2];
    $ETPath = 'ET' unless $ETPath;

    our $wuDataPath = $ARGV[3];
    $wuDataPath = 'wuData' unless $wuDataPath;

    our $WPPath = $ARGV[4];
    $WPPath = 'weatherprograms' unless $WPPath;
# My debugging code
    our $today = int($ARGV[5]);
    $today = '' unless ($today);
#
 	print "E: Today = $today\n" if $debug != 0;

# get variables passed from os through the main.js
#HP I think this is opensprinkler stuff?
#form = cgi.FieldStorage()
#loc  = form.getfirst('loc', '')
#key  = form.getfirst('key', '')
#of   = form.getfirst('format', '')
#pw   = form.getfirst('pw', '')
#pid  = safe_int(form.getfirst('pid', ''))  # program id for weather program that uses this adjustment we will need to read the log for it

#HP Is this needed??
##rainfallsatpoint = form.getfirst('rsp', '25')  # maximum rain to be used for ET calculations

######## Test Data Section #############
# Pull some of the data from the env instead of hard coding it
#myurl = os.getenv('NJCURL',   'http://mozart.uucp/data/') # this way I'm not downloading from WU during test
#loc   = os.getenv('NJCLOC',   '')                         # where's waldo? ;-)
#key   = os.getenv('WUKEY',    '')

#########Dummy Data Section ############
    our $loc  = '40.00,-74.00';
    our $key  = 'bad_key_DontUse';
    our $of   = 'json';
    our $tzone;
   
#HP - WHAT is THIS?? I _think_ it might be the opensprinkler Program ID
#if pid == 0:
    our $pid  = 2;
#

$loc = $config_parms{eto_location};
$key = $config_parms{wu_key};

# This will create an effective maximum for rain
# ...after this rain will not cause negative ET calculations (huh?)

	my $rainfallsatpoint = 25;

#########################################
## We need your latitude and longitude ##
## Let's try to get it with no api call##
#########################################

# Hey we were given what we needed let's work with it
	our ($lat,$t1,$lon) = $loc =~ /^([-+]?\d{1,2}([.]\d+)?),\s*([-+]?\d{1,3}([.]\d+)?)$/;
	$lat = "None" unless ($lat);
	$lon = "None" unless ($lon);

# We got a 5+4 zip code, we only need the 5
    $loc =~ s/\-\d\d\d\d//;
#

# We got a pws id, we don't need to tell wunderground,
# they know how to deal with the id numbers
    $loc =~ s/'pws:'//;
#



# Okay we finally have our loc ready to look up
#HP TODO - haven't tested this yet
	my $noData = 0;
	my ($whttyp,$ploc);
	if ($lat eq "None" and $lon eq "None") {
	    my $ua = new LWP::UserAgent( keep_alive => 1 );

        my $request = HTTP::Request->new( GET => "http://autocomplete.wunderground.com/aq?format=json&query=$loc" );
        my $responseObj = $ua->request($request);
        my $data;
        eval { $data = JSON::XS->new->decode( $responseObj->content ); };
        my $responseCode = $responseObj->code;
        my $isSuccessResponse = $responseCode < 400;
        if ( $isSuccessResponse ) {
        if (defined $data->{RESULTS}) {
            my $chk = $data->{RESULTS}[0]->{ll};  # # ll has lat and lon in one spot no matter how we search
            if ($chk) {
                my @ll = split(' ', $chk);
                if (scalar (@ll) == 2 and isFloat($ll[0]) and isFloat($ll[1])) {
                    $lat = $ll[0];
                    $lon = $ll[1];
                }
            }
            #
            my $chk = $data->{RESULTS}[0]->{tz};
            if ($chk) {
                $tzone = $chk;
            } else {
                my $chk2 = $data->{RESULTS}[0]->{tz_long};
                if ($chk2) {
                    $tzone = $chk2;
                }
            }
            #
            $chk = $data->{RESULTS}[0]->{name};  # # this is great for showing a pretty name for the location
            if ($chk) {
                $ploc = $chk;
            }
            #
            $chk = $data->{RESULTS}[0]->{type};
            if ($chk) {
                $whttyp = $chk;
            }
		} else {
		    $tzone = "None";
		}


		} else {
        	$noData = 1;
        	$lat    = "None";
        	$lon    = "None";
        	$tzone  = "None";
        	$ploc   = "None";
        	$whttyp = "None";
        }
	}
# Okay if all went well we got what we needed and snuck in a few more items we'll store those somewhere

	if ($lat and $lon) {
    	if ($lat and $lon and $whttpy and $ploc) {
        	print "For the $whttyp named: $ploc the lat, lon is: $lat, $lon, and the timezone is $tzone\n";
		} else {
        	print "Resolved your lat:$lat, lon:$lon, they will be stored\n";
        }
    	$loc = $lat . ',' . $lon;
	} else {
    	if ($noData) {
        	print "Oops couldn't reach Weather Underground check connection\n";
    	} else {
        	print "Oops $loc can't resolved try another location\n";
    	}
    }
    #
#


# -[ Main ]---------------------------------------------------------------------

# Get the weather info from Weather Underground
	our ($wuData, $offsets) = getwuData;
# I've inherited the code above and I haven't finished checking the code to see
# that it catches errors properly
	unless ($wuData) {
    	print "E: WU data appears to be empty, exiting\n";
    	exit;
    }
#
# Calculate an adjustment based on predicted rainfall
	my $tadjust = getForecastData($wuData->{forecast}->{simpleforecast}->{forecastday});
# sunrise and sunset times in minutes from midnight
#print "m2 tadjust = $tadjust\n";
	my $sun     = getAstronomyData($wuData->{sun_phase});
# 
#print "m3 = " . $sun->{rise} . "," . $sun->{set} . "\n";
	my ($todayRain, $noWater, $whyNot) = getConditionsData($wuData->{current_observation}, $wuData->{forecast}->{simpleforecast}->{forecastday}[0]);

######################## Quick Ref Names For wuData ########################################
	my $hist = $wuData->{history}->{dailysummary}[0];
#print "m3.1\n";
#print Dumper $hist;
########################### Required Data ##################################################
	$lat           	  = safe_float($lat);
	my $tmin          = safe_float($hist->{mintempm});
	my $tmax          = safe_float($hist->{maxtempm});
	my $tmean         = ($tmin + $tmax) / 2;
	my $alt           = safe_float($wuData->{current_observation}->{display_location}->{elevation});
	my $tdew          = safe_float($hist->{meandewptm});
	my $doy			  = Day_of_Year($hist->{date}->{year}, $hist->{date}->{mon}, $hist->{date}->{mday});
	my $sun_hours     = sun_block($sun->{rise}, $sun->{set});
	my $rh_min        = safe_float($hist->{minhumidity});
	my $rh_max        = safe_float($hist->{maxhumidity});
	my $rh_mean       = ($rh_min + $rh_max) / 2;
	my $meanwindspeed = safe_float($hist->{meanwindspdm});
	my $rainfall      = min(safe_float($hist->{precipm}), safe_float($rainfallsatpoint));

############################################################################################
##                             Calculations                                               ##
############################################################################################
# Calc Rn
print "pl1 [lat=$lat,tmin=$tmin,tmax=$tmax,tmean=$tmean,alt=$alt,tdew=$tdew,doy=$doy,shour=$sun_hours,rmin=$rh_min,rmax=$rh_max,$meanwindspeed,$rainfall,$rainfallsatpoint]\n";
	my $e_tmin   = &eto::delta_sat_vap_pres($tmin);
	my $e_tmax   = &eto::delta_sat_vap_pres($tmax);
	my $sd       = &eto::sol_dec($doy);
	my $sha      = &eto::sunset_hour_angle($lat, $sd);
	my $dl_hours = &eto::daylight_hours($sha);
	my $irl      = &eto::inv_rel_dist_earth_sun($doy);
	my $etrad    = &eto::et_rad($lat, $sd, $sha, $irl);
	my $cs_rad   = &eto::clear_sky_rad($alt, $etrad);
	my $Ra       = "";

print "pl2 [e_tmin=$e_tmin e_tmax=$e_tmax sd=$sd sha=$sha dl_hours=$dl_hours irl=$irl etrad=$etrad cs_rad=$cs_rad]\n";

    my $sol_rad = &eto::sol_rad_from_sun_hours($dl_hours, $sun_hours, $etrad);
    $sol_rad = &eto::sol_rad_from_t($etrad, $cs_rad, $tmin, $tmax) unless ($sol_rad);
    unless ($sol_rad) {
        print "Data for Penman-Monteith ETo not available reverting to Hargreaves ETo\n";
        # Calc Ra
        $Ra = $etrad;
        print "Not enough data to complete calculations" unless ($Ra);
    }


    my $ea = &eto::ea_from_tdew($tdew);
    $ea = &eto::ea_from_tmin($tmin) unless ($ea);
    $ea = &eto::ea_from_rhmin_rhmax($e_tmin, $e_tmax, $rh_min, $rh_max) unless ($ea);
    $ea = &eto::ea_from_rhmax($e_tmin, $rh_max) unless ($ea);
    $ea = &eto::ea_from_rhmean($e_tmin, $e_tmax, $rh_mean) unless ($ea);
    print "Failed to set actual vapor pressure" unless ($ea);


	my $ni_sw_rad = &eto::net_in_sol_rad($sol_rad);
	my $no_lw_rad = &eto::net_out_lw_rad($tmin, $tmax, $sol_rad, $cs_rad, $ea);
	my $Rn = &eto::net_rad($ni_sw_rad, $no_lw_rad);

# Calc t

	my $t = ($tmin + $tmax) / 2;

# Calc ws (wind speed)

	my $ws = &eto::wind_speed_2m($meanwindspeed, 10);

# Calc es

	my $es = &eto::mean_es($tmin, $tmax);

print "pl3 [sol_rad=$sol_rad ra=$Ra ea=$ea ni_sw_rad=$ni_sw_rad no_lw_rad=$no_lw_rad rn=$Rn t=$t ws=$ws es=$es]\n";

# ea done in Rn calcs
# Calc delta_es

	my $delta_es = &eto::delta_sat_vap_pres($t);

# Calc psy

	my $atmospres = &eto::atmos_pres($alt);
	my $psy       = &eto::psy_const($atmospres);
print "pl4 [delta_es=$delta_es atmospres=$atmospres psy=$psy]\n";
############################## Print Results ###################################

	print "$tadjust mm precipitation forecast for next 3 days\n";  # tomorrow+2 days forecast rain
	print "$todayRain mm precipitation fallen and forecast for today\n";  # rain fallen today + forecast rain for today
	# Binary watering determination based on 3 criteria: 1)Currently raining 2)Wind>8kph~5mph 3)Temp<4.5C ~ 40F
    print "We will not water because: $whyNot" if ($noWater);
	my ($ETdailyG, $ETdailyS);
	if (not $Ra) {
		#need better round function.
    	$ETdailyG = &eto::ETo($Rn, $t, $ws, $es, $ea, $delta_es, $psy, 0) - $rainfall; #ETo for most lawn grasses
    	$ETdailyS = &eto::ETo($Rn, $t, $ws, $es, $ea, $delta_es, $psy, 1) - $rainfall; #ETo for decorative grasses, most shrubs and flowers
    	print "P-M ETo\n";
    	print "$ETdailyG mm lost by grass\n";
    	print "$ETdailyS mm lost by shrubs\n";
    } else {
    #HP what does this do?? ETdailyG = ETdailyS = round(hargreaves_ETo(tmin, tmax, tmean, Ra) - rainfall, 4)
    #HP I think it sets two variables to the same result, so let's go with that.
    	$ETdailyG = &eto::hargreaves_ETo($tmin, $tmax, $tmean, $Ra) - $rainfall;
    	$ETdailyS = $ETdailyG;
    	print "H ETo\n";
    	print "$ETdailyG mm lost today\n";
    }

	print "sunrise & sunset in minutes from midnight local time\n";
	print $sun->{rise} . ' ' . $sun->{set} . "\n";
	writeResults($ETdailyG, $ETdailyS);

#Write the WU data to a file. This can be used for the MH weather data and save an api call

	my $fname = int((time - (time % 86400) -1) / 86400);
	$fname = $today if ($today);
	if (open (FILE, ">$wuDataPath/$fname")) {
		print FILE "observation_epoch, " . $wuData->{current_observation}->{observation_epoch} . "\n";
		print FILE "weather, " . $wuData->{current_observation}->{weather} . "\n";
		print FILE "temp_c, " . $wuData->{current_observation}->{temp_c} . "\n";
		print FILE "temp_f, " . $wuData->{current_observation}->{temp_f} . "\n";
		print FILE "relative_humidity, " . $wuData->{current_observation}->{relative_humidity} . "\n";
		print FILE "wind_degrees, " . $wuData->{current_observation}->{wind_degrees} . "\n";
		print FILE "wind_mph, " . $wuData->{current_observation}->{wind_mph} . "\n";
		print FILE "wind_kph, " . $wuData->{current_observation}->{wind_kph} . "\n";
		print FILE "precip_1hr_in, " . $wuData->{current_observation}->{precip_1hr_in} . "\n";
		print FILE "precip_1hr_metric, " . $wuData->{current_observation}->{precip_1hr_metric} . "\n";
		print FILE "precip_today_string, " . $wuData->{current_observation}->{precip_today_string} . "\n";
		print FILE "precip_today_in, " . $wuData->{current_observation}->{precip_today_in} . "\n";
		print FILE "precip_today_metric, " . $wuData->{current_observation}->{precip_today_metric} . "\n";
		print FILE "noWater, " . $noWater . "\n";		
		close (FILE);
	} else {	
		print "Can't open file $wuDataPath/$fname for writing!\n";
	}

# -[ fini ]---------------------------------------------------------------------

##Functions
##---------
##Atmospheric pressure (P):
##    atmos_pres(alt)
##Actual vapour pressure (ea):
##    ea_from_tdew(tdew)
##    ea_from_twet_tdry(twet, tdry, e_twet, psy_const)
##    ea_from_rhmin_rhmax(e_tmin, e_tmax, rh_min, rh_max)
##    ea_from_rhmax(e_tmin, rh_max)
##    ea_from_rhmean(e_tmin, e_tmax, rh_mean)
##    ea_from_tmin(tmin)
##Evapotranspiration over grass or shrubs (ETo):
##    ETo(Rn, t, ws, es, ea, delta_es, psy, crop=0, shf=0.0)
##    hargreaves_ETo(tmin, tmax, tmean, Ra)
##Pyschrometric constant:
##    psy_const(atmos_pres)
##    psy_const_of_psychrometer(psychrometer, atmos_pres)
##Radiation:
##    sol_rad_from_sun_hours(dl_hours, sun_hours, et_rad)
##    sol_rad_from_t(et_rad, cs_rad, tmin, tmax, coastal=-999)
##    sol_rad_island(et_rad) -only useful for monthly calculations
##    net_rad(ni_sw_rad, no_lw_rad)
##    clear_sky_rad(alt, et_rad)
##    daylight_hours(sha)
##    net_in_sol_rad(sol_rad)
##    net_out_lw_rad(tmin, tmax, sol_rad, clear_sky_rad, ea)
##    rad2equiv_evap(energy)
##    et_rad(lat, sd, sha, irl)
##Relative humidity (RH):
##    rh_from_ea_es(ea, es)
##Saturated vapour pressure (es):
##    delta_sat_vap_pres(t)
##    mean_es(tmin, tmax)
##Soil heat flux:
##    daily_soil_heat_flux(t_cur, t_prev, delta_t, soil_heat_cap=2.1, delta_z=0.10)
##Solar angles etc:
##    inv_rel_dist_earth_sun(doy)
##    sol_dec(doy)
##    sunset_hour_angle(lat, sd)
##Temperature:
##    daily_mean_t(tmin, tmax)
##Wind speed:
##    wind_speed_2m(meas_ws, z)

# -[ Notes ]--------------------------------------------------------------------
# https://opensprinkler.com/forums/topic/penmen-monteith-eto-method-python-script-for-possible-use-as-weather-script/
# https://www.hackster.io/Dan/particle-photon-weather-station-462217
# http://www.wunderground.com/weather/api/d/docs?d=resources/phrase-glossary
# http://www.fao.org/docrep/x0490e/x0490e08.htm (Chapter 4 - Determination of ETo)
# http://httpbin.org/
# ------------------------------------------------------------------------------
