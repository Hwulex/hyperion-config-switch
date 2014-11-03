#! /bin/bash
# Script to switch configuration files and to turn
# Hyperion LEDs on and off dependent on Network AVR
# (such as Pioneer 1X2X series, Onkyo, and Denon)
# Author: Dominic Wrapson <hwulex@gmail.com>
# License: The MIT License (MIT)
# http://choosealicense.com/licenses/mit/


# Exit script if try to use an uninitialised variable
set -u

# Check for and load config
config="hyperion-config-switch.conf"
if [ ! -e "$config" ]; then
	echo "Fatal error: Config file not found"
fi
source "$config" &> /dev/null

# Check for and load AVR parameters
avrconf="avr.conf"
if [ ! -e "$avrconf" ]; then
	echo "Fatal error: Config file not found"
fi
source "$avrconf" &> /dev/null


# Remote durations are in miliseconds but bash sleeps in seconds so do some conversion
off_sleep=$(((off_duration+1000)/1000))
on_sleep=$(((on_duration+1000)/1000))

{
	echo "[$(date "+%F %T")] Starting loop"

	while :
	do
		echo "[$(date "+%F %T")] Starting netcat"

		nc $avr_ip $avr_port | while read line
		do
            match=$(echo "$line" | grep -c "^$src_prefix\|$pwr_prefix")
			if [ "$match" -eq 1 ]; then
				# clean the input
				line=${line//[^a-zA-Z0-9]/}

				# Pull in config-saved previous state of AVR. Supress output in case doesn't already exist
				if [ ! -e $tmp ]
				then
					echo "[$(date "+%F %T")] Settings file not found, creating"
					echo "POWER=1" > $tmp
					echo "INPUT=FN00" >> $tmp
				fi
				echo "[$(date "+%F %T")] Reading settings file"
				source $tmp &> /dev/null
				echo "[$(date "+%F %T")] Setting INPUT=$INPUT"
				echo "[$(date "+%F %T")] Setting POWER=$POWER"

				# Switch dependant on reult of power-query
				# case "${line:0:2}:$line" in
				case "$line" in
				# case "$(echo $line|head -c2)" in

					# power is off
					"$pwr_off")
						echo "[$(date "+%F %T")] Power state changed: $line"

						# Visual effect, if wanted, to confirm power off
						# Remember 1 is off, 0 is on
						if [ "0" = "$POWER" ] && [ -n "$path_remote" ]
						then
							echo "[$(date "+%F %T")] AVR powered off: $off_effect"
							`${path_remote} --effect "${off_effect}" --duration ${off_duration} &`
							sleep $off_sleep
						fi

						# Sending black at a low channel (zero) effectively switching off leds
						# suggestion from tvdzwan (https://github.com/tvdzwan/hyperion/issues/177#issuecomment-58793948)
						eval "$path_remote --priority 0 --color black"

						# Save (backward) power state to config file
						echo POWER=1 > $tmp
						echo INPUT=$INPUT >> $tmp
						;;

					# power is on!
					"$pwr_on")
						echo "[$(date "+%F %T")] Power state changed: $line"

						# Remove the channel block by clearing selected channel
						# Again suggested by tvdzwan, see above for link
						eval "$path_remote --priority 0 --clear"

						# Trigger an effect here, if you like, as visual confirmation  we're back
						# Remember 1 is off, 0 is on
						if [ "1" = "$POWER" ] && [ -n "$path_remote" ]
						then
							echo "[$(date "+%F %T")] AVR powered on: config-file on-effect will show"
							eval $path_reload
							sleep $on_sleep
						fi

						# Save (backward) power state to config file
						echo POWER=0 > $tmp
						echo INPUT=$INPUT >> $tmp
						;;

					# Invalid option, query or result must have failed
					"$pwr_prefix"*)
						echo "[$(date "+%F %T")] Power detection failed. Invalid option: $line"
						;;

					# Input specific config file: What each of these correspond to can be found on the github readme/wiki
					"$src_prefix"*)

						# Read previous input of amp from last query and see if changed, otherwise don't bother
						if [ "$line" != "$INPUT" ]
						then
							echo "[$(date "+%F %T")] Input changed: $line"

							# Input specific config availability, otherwise will default
							if [[ "$line" =~ "$src_custom" ]]
								# Check to see if a valid config file for switched input actually exists
								if [ -e "${path_config}hyperion.config.${line}.json" ]
								then
									# Change config file to input-specific one
									echo "[$(date "+%F %T")] Switching to $line config file"
									new_config="${path_config}hyperion.config.$line.json"
								else
									# Input is setup but config file is not found, default it
									echo "[$(date "+%F %T")] Input specific config file not found, switching to default"
									new_config="${path_config}hyperion.config.default.json"
								fi
							else
								# Set config to default file, if not already set
								echo "[$(date "+%F %T")] Switching to default config file"
								new_config="${path_config}hyperion.config.default.json"
							fi

							# Check to see if the config file will actually be changing
							current_config=`ls -l $path_config | awk '{print $11}' | awk 1 ORS=''`
							if [ "$current_config" != "$new_config" ]
							then
								# Force the config change upon Hyperion
								eval "ln -s ${new_config} ${path_config}hyperion.config.json -f"
								echo "[$(date "+%F %T")] Config file switched, restarting Hyperion"
								eval $path_reload
							else
								echo "[$(date "+%F %T")] Requested config file already in use, leaving as is"
							fi
						fi

						# Write current input to config for next check
						echo POWER=$POWER > $tmp
						echo INPUT=$line >> $tmp
						;;

					# Nothing matched, somehow something unrecognised slipped through
					*)
						echo "[$(date "+%F %T")] Bad request, unsupported AVR code: $line"
						;;

				esac

			fi
		done

		echo "[$(date "+%F %T")] Netcat has stopped or crashed"

		sleep 4s
	done
} >> $log 2>&1