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
	NEXTUPDATE=-1  # Initialize to invalid value

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
			logger "Schedule $schedule active, interval is $INTERVAL minutes"
			CANDIDATE_UPDATE=$(( $CURRENTMINUTE + $INTERVAL))
			if [ $NEXTUPDATE -eq -1 ] || [ $CANDIDATE_UPDATE -lt $NEXTUPDATE ]; then
				NEXTUPDATE=$CANDIDATE_UPDATE
			fi

		# if the next update would fall into a following schedule entry
		elif [ $NEXTUPDATE -ne -1 ] && [ $(( $START + $INTERVAL )) -lt $NEXTUPDATE ]; then
			logger "Selected timeout will overlap $schedule, applying it instead"
			NEXTUPDATE=$(( $START + $INTERVAL ))
		fi
	done

	if [ $NEXTUPDATE -eq -1 ]; then
		# No valid schedule found, use default interval
		NEXTUPDATE=$(( $CURRENTMINUTE + ${INTERVAL:-240} ))
		logger "No active schedule, using default interval"
	fi

	MINUTES_TO_WAIT=$(( $NEXTUPDATE - $CURRENTMINUTE ))
	
	# If we're already past the update time, schedule for next interval
	if [ $MINUTES_TO_WAIT -le 0 ]; then
		logger "Past scheduled time, triggering update now"
		echo 0
	else
		logger "Next update in $MINUTES_TO_WAIT minutes"
		echo $MINUTES_TO_WAIT
	fi
}

##############################################################################

# perform update with timeout protection (Kindle-compatible)
do_update_cycle () {
	logger "Starting update cycle"
	
	# Run the update in background
	sh ./update.sh &
	UPDATE_PID=$!
	
	# Wait for update to complete with timeout
	TIMEOUT=300  # 5 minutes
	ELAPSED=0
	
	while [ $ELAPSED -lt $TIMEOUT ]; do
		if ! kill -0 $UPDATE_PID 2>/dev/null; then
			# Process has finished
			wait $UPDATE_PID
			UPDATE_RESULT=$?
			if [ $UPDATE_RESULT -eq 0 ]; then
				logger "Update completed successfully in $ELAPSED seconds"
			else
				logger "Update failed with exit code $UPDATE_RESULT after $ELAPSED seconds"
			fi
			return
		fi
		
		sleep 5
		ELAPSED=$(( $ELAPSED + 5 ))
	done
	
	# Timeout reached - kill the update process
	logger "Update timed out after $TIMEOUT seconds, killing process $UPDATE_PID"
	kill $UPDATE_PID 2>/dev/null
	sleep 2
	kill -9 $UPDATE_PID 2>/dev/null  # Force kill if still running
	
	logger "Update cycle finished (timed out)"
}

##############################################################################

# use a 48 hour schedule
extend_schedule

# Main execution loop with error recovery
while true; do
	DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status)
	logger "Device status: $DEVICE_STATUS"
	
	case "$DEVICE_STATUS" in
		*"Screen Saver"*)
			logger "Device in screensaver mode - performing scheduled update"
			
			# Record start time for timeout detection
			UPDATE_START_TIME=$(currentTime)
			do_update_cycle
			UPDATE_END_TIME=$(currentTime)
			UPDATE_DURATION=$(( $UPDATE_END_TIME - $UPDATE_START_TIME ))
			
			logger "Update took $UPDATE_DURATION seconds"
			
			# Wait for next scheduled update
			WAIT_MINUTES=$(get_time_to_next_update)
			logger "Next update in $WAIT_MINUTES minutes, sleeping until then"
			wait_for_suspend $(( $WAIT_MINUTES * 60 ))
			;;
		*"Ready"*)
			logger "Device ready - performing scheduled update"
			
			# Record start time for timeout detection
			UPDATE_START_TIME=$(currentTime)
			do_update_cycle
			UPDATE_END_TIME=$(currentTime)
			UPDATE_DURATION=$(( $UPDATE_END_TIME - $UPDATE_START_TIME ))
			
			logger "Update took $UPDATE_DURATION seconds"
			
			# Wait for next scheduled update  
			WAIT_MINUTES=$(get_time_to_next_update)
			logger "Next update in $WAIT_MINUTES minutes, sleeping until then"
			wait_for_suspend $(( $WAIT_MINUTES * 60 ))
			;;
		*)
			logger "Device in other state, waiting 60 seconds before recheck"
			wait_for_suspend 60
			;;
	esac
	
	# Safety check - if we somehow get here without sleeping, add a small delay
	sleep 1
done
