#!/bin/sh
#
##############################################################################
#
# Battery-efficient weather screensaver scheduler for Kindle
#
# Features:
#   - updates on schedule while allowing device suspension
#   - uses RTC wakeup to minimize battery drain
#   - only stays awake during actual updates
#   - handles screensaver and ready states efficiently
#
##############################################################################

# change to directory of this script
cd "$(dirname "$0")"

# load configuration
if [ -e "config.sh" ]; then
	source ./config.sh
else
	# set default values
	INTERVAL=240
	RTC=0
fi

# load utils
if [ -e "utils.sh" ]; then
	source ./utils.sh
else
	echo "Could not find utils.sh in `pwd`"
	exit 1
fi

###############################################################################

# create a two day filling schedule
extend_schedule () {
	SCHEDULE_ONE=""
	SCHEDULE_TWO=""

	LASTENDHOUR=0
	LASTENDMINUTE=0
	LASTEND=0
	for schedule in $SCHEDULE; do
		read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE THISINTERVAL << EOF
			$( echo " $schedule" | sed -e 's/[:,=,\,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g')
EOF
		START=$(( 60*$STARTHOUR + $STARTMINUTE ))
		END=$(( 60*$ENDHOUR + $ENDMINUTE ))

		# if the previous schedule entry ended before this one starts,
		# create a filler
		if [ $LASTEND -lt $START ]; then
			SCHEDULE_ONE="$SCHEDULE_ONE $LASTENDHOUR:$LASTENDMINUTE-$STARTHOUR:$STARTMINUTE=$DEFAULTINTERVAL"
			SCHEDULE_TWO="$SCHEDULE_TWO $(($LASTENDHOUR+24)):$LASTENDMINUTE-$(($STARTHOUR+24)):$STARTMINUTE=$DEFAULTINTERVAL"
		fi
		SCHEDULE_ONE="$SCHEDULE_ONE $schedule"
		SCHEDULE_TWO="$SCHEDULE_TWO $(($STARTHOUR+24)):$STARTMINUTE-$(($ENDHOUR+24)):$ENDMINUTE=$THISINTERVAL"
		
		LASTENDHOUR=$ENDHOUR
		LASTENDMINUTE=$ENDMINUTE
		LASTEND=$END
	done

	# check that the schedule goes to midnight
	if [ $LASTEND -lt $(( 24*60 )) ]; then
		SCHEDULE_ONE="$SCHEDULE_ONE $LASTENDHOUR:$LASTENDMINUTE-24:00=$DEFAULTINTERVAL"
		SCHEDULE_TWO="$SCHEDULE_TWO $(($LASTENDHOUR+24)):$LASTENDMINUTE-48:00=$DEFAULTINTERVAL"
	fi
	
	# to handle the day overlap, append the schedule again for hours 24-48.
	SCHEDULE="$SCHEDULE_ONE $SCHEDULE_TWO"
	logger "Full two day schedule: $SCHEDULE"
}

##############################################################################

# return number of minutes until next update
get_time_to_next_update () {
	CURRENTMINUTE=$(( 60*`date +%-H` + `date +%-M` ))

	for schedule in $SCHEDULE; do
		read STARTHOUR STARTMINUTE ENDHOUR ENDMINUTE INTERVAL << EOF
			$( echo " $schedule" | sed -e 's/[:,=,\,,-]/ /g' -e 's/\([^0-9]\)0\([[:digit:]]\)/\1\2/g' )
EOF
		START=$(( 60*$STARTHOUR + $STARTMINUTE ))
		END=$(( 60*$ENDHOUR + $ENDMINUTE ))

		# ignore schedule entries that end prior to the current time
		if [ $CURRENTMINUTE -gt $END ]; then
			continue

		# if this schedule entry covers the current time, use it
		elif [ $CURRENTMINUTE -ge $START ] && [ $CURRENTMINUTE -lt $END ]; then
			logger "Schedule $schedule used, next update in $INTERVAL minutes"
			NEXTUPDATE=$(( $CURRENTMINUTE + $INTERVAL))

		# if the next update falls into (or overlaps) a following schedule
		# entry, apply this schedule entry instead if it would trigger earlier
		elif [ $(( $START + $INTERVAL )) -lt $NEXTUPDATE ]; then
			logger "Selected timeout will overlap $schedule, applying it instead"
			NEXTUPDATE=$(( $START + $INTERVAL ))
		fi
	done

	logger "Next update in $(( $NEXTUPDATE - $CURRENTMINUTE )) minutes"
	echo $(( $NEXTUPDATE - $CURRENTMINUTE ))
}

##############################################################################

# perform update and handle power management efficiently
do_update_cycle () {
	logger "Starting update cycle"
	
	# Run the update
	sh ./update.sh
	
	# Get time until next update
	WAIT_MINUTES=$(get_time_to_next_update)
	WAIT_SECONDS=$(( $WAIT_MINUTES * 60 ))
	
	logger "Next update in $WAIT_MINUTES minutes ($WAIT_SECONDS seconds)"
	
	# Set RTC wakeup for next update
	set_rtc_wakeup_absolute $WAIT_SECONDS
	
	# Allow device to suspend after a brief delay
	sleep 2
	logger "Update cycle complete, allowing device to suspend"
}

##############################################################################

# use a 48 hour schedule
extend_schedule

# Main execution loop - much simpler and battery efficient
while true; do
	DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status)
	logger "Device status: $DEVICE_STATUS"
	
	case "$DEVICE_STATUS" in
		*"Screen Saver"*)
			logger "Device in screensaver mode - performing update"
			do_update_cycle
			;;
		*"Ready"*)
			logger "Device ready - performing update"
			do_update_cycle
			;;
		*"Charging: Yes"*)
			logger "Device charging - performing update"
			do_update_cycle
			;;
		*)
			logger "Device in other state, waiting 30 seconds before recheck"
			# Use RTC wakeup even for short waits to save power
			set_rtc_wakeup_absolute 30
			sleep 30
			;;
	esac
done