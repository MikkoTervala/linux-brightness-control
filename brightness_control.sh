#!/bin/bash

# Check if the script is being run as a systemd service
# if [[ $1 == "systemd" ]]; then
  # Redirect all output to /dev/null
exec >/dev/shm/brightness_control.log 2>&1
# fi

echo "Starting brightness control"

# Number of measurements in seconds
NUM_MEASUREMENTS=60

# Gamma correction value
gamma=1.8

# Wildcard pattern for file search
FILE_PATTERN="/sys/bus/iio/devices/iio:device*/in_illuminance_raw"

# Scaling function with linear transformation and gamma correction
scale_value() {
  local value="$1"

  # Scaling parameters (adjusted)
  min_value=200
  max_value=1000000
  min_output=1
  max_output=100

  # Ensure value is within range
  if ((value < min_value)); then
    value=$min_value
  elif ((value > max_value)); then
    value=$max_value
  fi

  # Calculate the linearly scaled value
  linear_scaled_value=$(( (value - min_value) * (max_output - min_output) / (max_value - min_value) + min_output ))

  # Apply gamma correction
  gamma_scaled_value=$(awk -v lsv="$linear_scaled_value" -v gamma="$gamma" 'BEGIN{print int(100*((lsv/100)^(1/gamma)))}')

  echo "$gamma_scaled_value"
}

# Function to set display brightness
set_brightness() {
  local brightness="$1"

  # Check if /tmp/display_off file exists, if it does, set brightness to 0 and return
  if [ -f "/tmp/display_off" ]; then
    brightnessctl set 0% -q
    # echo "Display brightness set to 0% due to /tmp/display_off"
    return
  fi

  # Ensure brightness is within range
  if ((brightness < 1)); then
    brightness=1
  elif ((brightness > 100)); then
    brightness=100
  fi

  # Set the display brightness
  brightnessctl set "$brightness%" -q
  # echo "Display brightness set to $brightness%"
}


# Array to store the last NUM_MEASUREMENTS averages
averages=()

# Counter for setting the brightness every 5 seconds
counter=0

# Main loop
while true; do
  for file in $FILE_PATTERN; do
    if [[ -f "$file" ]]; then
      # Read the value from the file
      raw_value=$(cat "$file")

      # Scale the value with linear transformation and gamma correction
      scaled_value=$(scale_value "$raw_value")

      # Add the scaled value to the averages array
      averages+=("$scaled_value")

      # If we have more than NUM_MEASUREMENTS averages, remove the oldest one
      if (( ${#averages[@]} > NUM_MEASUREMENTS )); then
        averages=("${averages[@]:1}")
      fi

      # Calculate the average of the values in the averages array
      sum=0
      for value in "${averages[@]}"; do
        sum=$((sum + value))
      done
      average=$((sum / ${#averages[@]}))

      # echo "Rolling Average for ${file##*/}: $average% (Raw Value: $raw_value)"

      # Set the display brightness every 5 seconds
      if (( counter % 5 == 0 )); then
        set_brightness "$average"
      fi

      # Increment the counter
      counter=$((counter + 1))
    fi
  done

  # Sleep for 1 second
  sleep 1
done
