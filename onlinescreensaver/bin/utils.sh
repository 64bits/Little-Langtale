#!/bin/sh
##############################################################################
# Battery-efficient utility functions for Kindle scheduler
##############################################################################

##############################################################################
# Logs a message to a log file (or to console if argument is /dev/stdout)

logger () {
	MSG=$1
	
	# do nothing if logging is not enabled
	if [ "x1" != "x$LOGGING" ]; then
		return
	fi

	# if no logfile is specified, set a default
	if [ -z $LOGFILE ]; then
		LOGFILE=stdout
	fi

	echo `date`: $MSG >> $LOGFILE
}

##############################################################################
# Retrieves the current time in seconds

currentTime () {
	date +%s
}

##############################################################################
# Sets RTC wakeup using absolute time - more reliable than relative time
# arguments: $1 - time in seconds from now

set_rtc_wakeup_absolute () {
	WAKEUP_DELAY=$1
	CURRENT_TIME=$(currentTime)
	WAKEUP_TIME=$(( $CURRENT_TIME + $WAKEUP_DELAY ))
	
	logger "Setting RTC wakeup in $WAKEUP_DELAY seconds (absolute time: $WAKEUP_TIME)"
	
	# Clear any existing alarm
	echo 0 > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
	
	# Set new wakeup time
	echo $WAKEUP_TIME > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
	
	# Verify the alarm was set correctly
	SET_ALARM=$(cat /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null)
	if [ "$SET_ALARM" = "$WAKEUP_TIME" ]; then
		logger "RTC wakeup successfully set for $WAKEUP_TIME"
		return 0
	else
		logger "Warning: RTC wakeup setting failed. Wanted: $WAKEUP_TIME, Got: $SET_ALARM"
		return 1
	fi
}

##############################################################################
# Battery-efficient wait function that allows proper suspension
# arguments: $1 - time in seconds from now

wait_for_suspend () {
	WAIT_SECONDS=$1
	logger "Starting battery-efficient wait for $WAIT_SECONDS seconds"
	
	# Set RTC wakeup
	if set_rtc_wakeup_absolute $WAIT_SECONDS; then
		logger "RTC alarm set, allowing device to suspend"
		
		# Enable CPU power saving
		echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
		
		# Brief delay to ensure RTC is set, then allow natural suspension
		sleep 1
		
		# Wait for the wakeup event or timeout
		ENDTIME=$(( $(currentTime) + $WAIT_SECONDS ))
		while [ $(currentTime) -lt $ENDTIME ]; do
			# Use lipc-wait-event to efficiently wait for power events
			# This will return when device wakes up or timeout occurs
			lipc-wait-event -s $(( $ENDTIME - $(currentTime) )) com.lab126.powerd resuming,wakeupFromSuspend 2>/dev/null || break
			
			# Check if we've reached our target time
			if [ $(currentTime) -ge $ENDTIME ]; then
				break
			fi
		done
		
		logger "Wait completed, device should be awake"
	else
		logger "RTC wakeup failed, falling back to regular sleep"
		sleep $WAIT_SECONDS
	fi
}

##############################################################################
# Clean RTC wakeup function for device shutdown/cleanup
clear_rtc_wakeup () {
	logger "Clearing RTC wakeup alarm"
	echo 0 > /sys/class/rtc/rtc$RTC/wakealarm 2>/dev/null
}

##############################################################################
# Check if device should be allowed to suspend
can_suspend () {
	# Check if we're in a state where suspension is beneficial
	DEVICE_STATUS=$(lipc-get-prop com.lab126.powerd status 2>/dev/null)
	
	case "$DEVICE_STATUS" in
		*"Active"*)
			# Device is actively being used
			return 1
			;;
		*"Screen Saver"*|*"Ready"*)
			# Device can suspend
			return 0
			;;
		*)
			# Unknown state, allow suspension to be safe
			return 0
			;;
	esac
}

##############################################################################
# Optimized power management - reduces CPU usage and allows suspension
enable_power_savings () {
	logger "Enabling power saving optimizations"
	
	# Set CPU to power save mode
	if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
		echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
		logger "CPU set to powersave mode"
	fi
	
	# Reduce CPU frequency if possible
	if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed ]; then
		MIN_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null)
		if [ -n "$MIN_FREQ" ]; then
			echo $MIN_FREQ > /sys/devices/system/cpu/cpu0/cpufreq/scaling_setspeed 2>/dev/null
			logger "CPU frequency reduced to minimum: $MIN_FREQ"
		fi
	fi
}

##############################################################################
# Legacy functions kept for compatibility but improved

# Original wait_for function - improved for better power management
wait_for () {
	wait_for_suspend $1
}

# Improved version of the original wait_for_fixed
wait_for_fixed () {
	logger "wait_for_fixed() started with power optimizations"
	
	enable_power_savings
	
	# Use our improved suspend-friendly wait
	wait_for_suspend $1
	
	logger "wait_for_fixed() finished"
}

# runs when in the readyToSuspend state - improved version
set_rtc_wakeup() {
	logger "Setting rtcWakeup property to $1 seconds"
	lipc-set-prop -i com.lab126.powerd rtcWakeup $1 2>/dev/null
	
	# Also set direct RTC alarm as backup
	set_rtc_wakeup_absolute $1
}

##############################################################################
# Cleanup function for graceful shutdown
cleanup_and_exit () {
	logger "Performing cleanup before exit"
	clear_rtc_wakeup
	exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup_and_exit TERM INT QUIT