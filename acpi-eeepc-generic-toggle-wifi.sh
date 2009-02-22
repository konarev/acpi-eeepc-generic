#!/bin/bash
#
# http://code.google.com/p/acpi-eeepc-generic/
#

. /etc/acpi/eeepc/acpi-eeepc-generic-functions.sh

# Find the right rfkill switch, but default to the first one
rfkill="rfkill0"
lsrfkill=""
[ -e /sys/class/rfkill ] && lsrfkill=`/bin/ls /sys/class/rfkill/`
for r in $lsrfkill; do
    name=`cat /sys/class/rfkill/$r/name`
    if [ "$name" == "eeepc-wlan" ]; then
        msg="acpi-eeepc-generic-toggle-wifi.sh: Wifi rfkill switch find ($r)"
        logger $msg
        echo $msg
        rfkill=$r
    fi
done

RADIO_CONTROL_DEPRECATED=/proc/acpi/asus/wlan
RADIO_CONTROL_OTHER=/sys/devices/platform/eeepc/wlan
# Get rfkill switch state (0 = card off, 1 = card on)
RADIO_CONTROL="/sys/class/rfkill/${rfkill}/state"
if [ -e "$RADIO_CONTROL" ]; then
    RADIO_STATE=$(cat $RADIO_CONTROL)
else
    RADIO_STATE=0
    msg="acpi-eeepc-generic-toggle-wifi.sh: Wifi rfkill switch state does not exist. Using 0 as RADIO_STATE"
    logger $msg
    echo $msg
fi

# If the states has been saved, read that state. Else, get the
# actual state.
EEEPC_RADIO_SAVED_STATE_FILE=$EEEPC_VAR/states/wifi
if [ -e $EEEPC_RADIO_SAVED_STATE_FILE ]; then
  RADIO_SAVED_STATE=$(cat $EEEPC_RADIO_SAVED_STATE_FILE)
else
  RADIO_SAVED_STATE=$RADIO_STATE
fi

# Get wifi interface
WIFI_IF=$(/usr/sbin/iwconfig 2>/dev/null | grep ESSID | awk '{print $1}')

function radio_toggle {
    if [ "$RADIO_STATE" = "1" ]; then
        radio_off 1
    else
        radio_on 1
    fi
}

function radio_restore {
  if [ "$RADIO_SAVED_STATE" = "1" ]; then
    radio_on 1 0
  else
    radio_off 1 0
  fi
}

function debug_wifi() {
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): EeePC model: $EEEPC_MODEL ($EEEPC_CPU)"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): BIOS version: `dmidecode | grep -A 5 BIOS | grep Version | awk '{print ""$2""}'`"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Running kernel: `uname -a`"
    if [ -e /usr/bin/pacman ]; then
        echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Installed kernel(s):"
        echo "`/usr/bin/pacman -Qs kernel26`"
    fi
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Wifi rfkill: $RADIO_CONTROL"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Wifi state: $RADIO_STATE"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Wifi interface: $WIFI_IF"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): Wifi module: $WIFI_DRIVER"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): COMMANDS_WIFI_PRE_UP:"
    print_commands "${COMMANDS_WIFI_PRE_UP[@]}"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): COMMANDS_WIFI_POST_UP:"
    print_commands "${COMMANDS_WIFI_POST_UP[@]}"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): COMMANDS_WIFI_PRE_DOWN:"
    print_commands "${COMMANDS_WIFI_PRE_DOWN[@]}"
    echo "DEBUG (acpi-eeepc-generic-toggle-wifi.sh): COMMANDS_WIFI_POST_DOWN:"
    print_commands "${COMMANDS_WIFI_POST_DOWN[@]}"

    eeepc_notify "Can you see this?" gtk-dialog-question 10000
}

function radio_on {
    show_notifications=1
    [ "$2" == "0" ] && show_notifications=

    [ "$show_notifications" == "1" ] && \
        eeepc_notify "Turning WiFi Radio on..." gnome-dev-wavelan

    # Execute pre-up commands just once
    [ $1 -eq 1 ] && execute_commands "${COMMANDS_WIFI_PRE_UP[@]}"

    # Enable radio
    [ -e "$RADIO_CONTROL" ]            && echo 1 > $RADIO_CONTROL
    [ -e "$RADIO_CONTROL_DEPRECATED" ] && echo 1 > $RADIO_CONTROL_DEPRECATED
    [ -e "$RADIO_CONTROL_OTHER" ]      && echo 1 > $RADIO_CONTROL_OTHER

    # Load module
    /sbin/modprobe $WIFI_DRIVER 2>/dev/null
    success=$?
    if [ $success ]; then
        # If successful, enable card
        echo 1 > $EEEPC_RADIO_SAVED_STATE_FILE
        # Execute post-up commands
        execute_commands "${COMMANDS_WIFI_POST_UP[@]}"

        [ "$show_notifications" == "1" ] && eeepc_notify "WiFi Radio is now on" gnome-dev-wavelan
    else
        [ "$show_notifications" == "1" ] && eeepc_notify "Could not enable WiFi radio" stop
        # If module loading unsuccessful, try again
        if [ $1 -lt $WIFI_TOGGLE_MAX_TRY ]; then
            [ "$show_notifications" == "1" ] && \
                eeepc_notify "Trying again in 2 second ($(($1+1)) / $WIFI_TOGGLE_MAX_TRY)" gnome-dev-wavelan
            sleep 2
            radio_on $(($1+1)) $show_notifications
        fi
    fi
}

function radio_off {
    show_notifications=1
    [ "$2" == "0" ] && show_notifications=0

    [ "$show_notifications" == "1" ] && eeepc_notify "Turning WiFi Radio off..." gnome-dev-wavelan

    # Execute pre-down commands just once
    [ $1 -eq 1 ] && execute_commands "${COMMANDS_WIFI_PRE_DOWN[@]}"

    # Put interface down and wait 1 second
    /sbin/ifconfig $WIFI_IF down 2>/dev/null
    sleep 1

    # Unload module
    /sbin/modprobe -r $WIFI_DRIVER 2>/dev/null
    success=$?
    if [ $success ]; then
        # If successful, disable card through rkfill and save the state
        [ -e "$RADIO_CONTROL" ]            && echo 0 > $RADIO_CONTROL
        [ -e "$RADIO_CONTROL_DEPRECATED" ] && echo 0 > $RADIO_CONTROL_DEPRECATED
        [ -e "$RADIO_CONTROL_OTHER" ]      && echo 0 > $RADIO_CONTROL_OTHER

        echo 0 > $EEEPC_RADIO_SAVED_STATE_FILE

        # Execute post-down commands
        execute_commands "${COMMANDS_WIFI_POST_DOWN[@]}"

        [ "$show_notifications" == "1" ] && eeepc_notify "WiFi Radio is now off" gnome-dev-wavelan
    else
        # If module unloading unsuccessful, try again
        [ "$show_notifications" == "1" ] && eeepc_notify "Could not disable WiFi radio" stop
        if [ $1 -lt $WIFI_TOGGLE_MAX_TRY ]; then
                [ "$show_notifications" == "1" ] && \
                    eeepc_notify "Trying again in 2 second ($(($1+1)) / $WIFI_TOGGLE_MAX_TRY)" gnome-dev-wavelan
            sleep 2
            radio_off $(($1+1)) $show_notifications
        fi
    fi
}

case $1 in
    restore)
        radio_restore
    ;;
    stop|off)
        radio_off 1
    ;;
    start|on)
        radio_on 1
    ;;
    debug)
        debug_wifi
    ;;
    *)
        radio_toggle
    ;;
esac

