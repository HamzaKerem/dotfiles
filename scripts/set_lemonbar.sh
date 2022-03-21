#!/bin/sh
 
# Script constants
DEFAULT_SLEEP_TIME="1"

get_cpu_info()
{
	cpu_data="$(mpstat | awk 'NR==4')"
	usr_data="$(echo $cpu_data | cut -d ' ' -f 4)"
	sys_data="$(echo $cpu_data | cut -d ' ' -f 6)"

	echo "usr: ${usr_data} sys: ${sys_data}"
}

get_window_titles()
{
	recieved_window_titles=""
	temp_window_titles_file="$(mktemp)"
	
	# Output list_clients_output properly formatted to temp_window_titles_file
	echo "$list_clients_output" | cut -d ' ' -f 2- > "$temp_window_titles_file"
	
	while read -r line; do
		# Get only last string in the entire line
		space_count="$(echo "$line" | grep -o '[[:space:]]' | wc -l)"
		if ((space_count==0)); then
			single_window_title="$line"
		else
			single_window_title="$(echo "$line" | cut -d ' ' -f $((space_count+1)))"
		fi
		recieved_window_titles="${recieved_window_titles}${single_window_title} "
	done < "$temp_window_titles_file"

	rm "$temp_window_titles_file"
	echo "$recieved_window_titles"
}

get_hlwm_info()
{
	# Local constants
	SPACE_COUNT=20
	TOTAL_MONITOR_COUNT=4
	REGULAR_TAG_COLOR="#000000"
	CURRENT_TAG_COLOR="#FFFFFF"
	REGULAR_TAG_BG_COLOR="#EEFF7C"
	CURRENT_TAG_BG_COLOR="#DE6FFF"

	current_tag="$(herbstclient list_monitors | cut -d '"' -f 2)"
	
	# Print all tag boxes each containing tag number and window titles
	for tag in $(seq 1 $TOTAL_MONITOR_COUNT); do

		# Print color formatting
		if [ "$current_tag" = "$tag" ]; then
			printf -- "%s" "%{B${CURRENT_TAG_BG_COLOR}} %{F${CURRENT_TAG_COLOR}} "
		else
			printf -- "%s" "%{B${REGULAR_TAG_BG_COLOR}} %{F${REGULAR_TAG_COLOR}} "
		fi

		# Print regular tag number 
		printf "%s" "$tag"

		# Get window titles for each tag, print if applicable
		list_clients_output="$(herbstclient list_clients --tag="$tag" --title)"
		if [ -n "$list_clients_output" ]; then
			# Parse through the entire data and only get the program name
			window_titles="$(get_window_titles)"

			# Calculate number of spaces needed for the rest of the "tag box"
			window_titles_strlen=$(printf "%s" "$window_titles" | wc -c)
			spaces_left=$((SPACE_COUNT-window_titles_strlen-1))

			# Print window titles of the programs only
			printf " %s" "$window_titles"
		else
			spaces_left=$SPACE_COUNT
		fi

		# Print space
		for j in $(seq 1 $spaces_left); do
			printf "%s" " "
		done
	done
	printf -- "%s\n" "%{B${REGULAR_TAG_BG_COLOR}}"
}

get_acpi_info()
{
	charging_percentage="$(acpi | cut -d ' ' -f 4 | cut -b -3)"
	charging_status="$(acpi | cut -d ' ' -f 3 | cut -d ',' -f 1)"
	echo "${charging_status} ${charging_percentage}"
}

get_nmcli_info()
{
	con_line="$(nmcli device | awk 'NR==2')"
	echo $con_line
}

get_mpc_info()
{
	# Basic stuff
	vol="$(mpc status '%volume%')"
	song="$(mpc current)"
	songpos="$(mpc status '%songpos%')"
	pl_length="$(mpc status '%length%')"

	# Status stuff
	random_status="$(mpc status '%random%')"
	random_status_letter="."
	[ "$random_status" = "on" ] && random_status_letter="R"

	single_status="$(mpc status '%single%')"
	single_status_letter="."
	[ "$single_status" = "on" ] && single_status_letter="S"

	repeat_status="$(mpc status '%repeat%')"
	repeat_status_letter="."
	[ "$repeat_status" = "on" ] && repeat_status_letter="R"

	# If --ttf-font-awesome is passed, echo icon strings too
	if  [ "$ttf_fa_bool" = "true" ]; then
		state_status="$(mpc status '%state%')"
		[ "$state_status" = "playing" ] && state_icon="\\uf001"
		[ "$state_status" = "paused" ] && state_icon="\\uf05e"
	fi	

	echo "mpc volume:${vol} | ${song} (${songpos}/${pl_length}) " \
		"(${random_status_letter}${single_status_letter}${repeat_status_letter}) " \
		"${state_icon}"
}

get_date_info()
{
	date '+%T   %d/%B/%Y   %:z'
}

get_pulseaudio_info()
{
	echo "PA volume: $(pamixer --get-volume)"
}

call_later()
{
	passed_alignment_direction="$1"
	passed_executable_function="$2"

	# Create temp file if non-existent
	if [ ! -f "$temp_loop_file" ]; then
		temp_loop_file="$(mktemp)" || 
		{ printf -- "%s\n" "Fatal: Couldn't create temporary file. Exitting" 2>&1; exit 1; }
	fi
	
	# Write alignment_direction and executable_function to temp_loop_file
	#while read -r read_alignment_direction read_executable_function; do
		# If the passed alignment_direction is the same as the read one,
	    # append the passed exec function to the line 	
		#[ "$read_alignment_direction" = "$passed_alignment_direction" ] &&
		#:
	#done < "$temp_loop_file"
	printf -- "%s %s\n" "$1" "$2" >> "$temp_loop_file"
}

parse_options()
{
	# true if --ttf-font-awesome pos-param is passed
	ttf_fa_bool="false"
	# Result to default sleep_time if --sleep-time SLEEP_TIME isn't passed
	sleep_time="$DEFAULT_SLEEP_TIME"
	# default alignment direction is c (center)
	alignment_direction="c"

	while [ "$#" -gt 0 ]; do
		case "$1" in
			'--ttf-font-awesome') ttf_fa_bool="true";;	
			'--sleep-time') [ -n "$2" ] && sleep_time="$2";;
			'-l') alignment_direction="l";;
			'-r') alignment_direction="r";;
			'-c') alignment_direction="c";;
			*) output="$("$1" 2> /dev/null || printf -- "%s\n" "INVALID_INPUT")"; 
				[ "X$output" != "XINVALID_INPUT" ] && 
				call_later "$alignment_direction" "$1";;
		esac
	shift	
	done
}

lemonbar_loop()
{
	while true; do
	
		# Read string to output to lemonbar from temp_loop_file
		lemonbar_string=""
		while read alignment_direction_in executable_function_in; do
			lemonbar_string="${lemonbar_string} %{${alignment_direction_in}} $("$executable_function_in")"	
		done < "$temp_loop_file"
		
		# Output to lemonbar
		echo -e "$lemonbar_string"

		sleep "$sleep_time"
	done
}

# Parse pos-param options
parse_options "$@"

# If temp_loop_file is non-existent after pos-params are parsed, none were passed
[ ! -f "$temp_loop_file" ] && exit 0

# Loop over passed pos-param executable functions
lemonbar_loop 