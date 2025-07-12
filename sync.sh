#######################################
# Globals
#######################################
ARGS=()
DEVICE="-d"
SIMULATE=false
CAMERA=false
VIDEOS=false
PHOTOS=false
PULL=true
PUSH=false
PREFIX='sync:'

#######################################
# Format the string to info colors
#
# Arguments:
#   $1: String; to be formatted
# Outputs:
#   Writes the formatted string to stdout
#######################################
pinfo() {
    printf '\x1b[36m%s\x1b[0m' "$1"
}

#######################################
# Format the string to success colors
#
# Arguments:
#   $1: String; to be formatted
# Outputs:
#   Writes the formatted string to stdout
#######################################
psuccess() {
    printf '\x1b[1;32m%s\x1b[0m' "$1"
}

#######################################
# Format the string to error colors
#
# Arguments:
#   $1: String; to be formatted
# Outputs:
#   Writes the formatted string to stdout
#######################################
perror() {
    printf '\x1b[1;31m%s\x1b[0m' "$1"
}

#######################################
# Format the string to warn colors
#
# Arguments:
#   $1: String; to be formatted
# Outputs:
#   Writes the formatted string to stdout
#######################################
pwarn() {
    printf '\x1b[33m%s\x1b[0m' "$1"
}

#######################################
# Get the difference between the REMOTE
# files and the LOCAL files
#
# Arguments:
#   $1: Path; to REMOTE files
#   $2: Path; to LOCAL files
#   $3: Bool; TRUE=local files, FALSE=remote files 
# Outputs:
#   Writes diff to stdout
########################################
get_diff() {
    result=
    if [[ $3 == true ]]; then
        result="$(diff <(adb $DEVICE shell ls $1) <(ls $2) | grep '^>' | sed -e 's/> //')"
    else
        result="$(diff <(adb $DEVICE shell ls $1) <(ls $2) | grep '^<' | sed -e 's/< //')"
    fi
    printf "$result"
}

#######################################
# Get files from device 
#
# Globals:
#   DEVICE
#   SIMULATE
#   PREFIX
# Arguments:
#   $1: Path; to REMOTE files
#   $2: Path; to LOCAL files 
#######################################
pull_files() {
    PREFIX='pull:'
    files=()
    media_files="$(get_diff $1 $2)"

    if [[ -z $media_files ]]; then
        printf "%s no file(s) to pull from \x1b[1;36m'%s/'\x1b[0m\n" $(pwarn $PREFIX) $1
        return 0
    fi

    IFS=$'\n' read -d "" -ra unformated_files <<< "$media_files"
    for media in "${unformated_files[@]}"
    do
        files+=("$1/$media") 
    done
    printf "%s file(s) to pull from \x1b[1;36m'%s/'\x1b[0m:\n" $(pinfo $PREFIX) $1
    printf "\x1b[34m%s\x1b[0m\n" "${media_files[@]}"

    [[ $SIMULATE == false ]] && $(adb $DEVICE pull ${files[*]} "$2/" 2>>pull.log)

    if ! $SIMULATE  && [ $? -eq 0 ]; then
        printf "%s success pulling file(s) from \x1b[1;36m'%s'\x1b[0m\n" $(psuccess $PREFIX) $1
        return 0
    fi

    if [ $? -eq 1 ]; then
        printf "%s failed to pull file(s) from \x1b[1;36m'%s'\x1b[0m\n%s see 'pull.log' file for details\n" $(perror $PREFIX) $1 $(perror $PREFIX)
        return 1
    fi
}

#######################################
# Copy files to device 
#
# Globals:
#   DEVICE
#   SIMULATE
#   PREFIX
# Arguments:
#   $1: Path; to LOCAL files
#   $2: Path; to REMOTE files 
#######################################
push_files() {
    # adb -e push camera/FILE /sdcard/DCIM/Camera/FILE
    # push_files photos /sdcard/Pictures/photos
    # push [--sync] [-z ALGORITHM] [-Z] LOCAL... REMOTE
    PREFIX='push:'
    files=()
    media_files="$(get_diff $2 $1 true)"

    if [[ -z $media_files ]]; then
        printf "%s no file(s) to push to \x1b[1;36m'%s/'\x1b[0m\n" $(pwarn $PREFIX) $2
        return 0
    fi

    IFS=$'\n' read -d "" -ra unformated_files <<< "$media_files"
    for media in "${unformated_files[@]}"
    do
        files+=("$1/$media") 
    done
    printf "%s file(s) to push to \x1b[1;36m'%s/'\x1b[0m:\n" $(pinfo $PREFIX) $2
    printf "\x1b[34m%s\x1b[0m\n" "${media_files[@]}"

    if ! $SIMULATE; then
        $(adb $DEVICE push ${files[*]} "$2" 2>>push.log)
    fi

    if ! $SIMULATE && [ $? -eq 0 ]; then
        printf "%s success pushing file(s) to \x1b[1;36m'%s'\x1b[0m\n" $(psuccess $PREFIX) $2
        return 0
    fi

    if [ $? -eq 1 ]; then
        printf "%s failed to push file(s) to \x1b[1;36m'%s'\x1b[0m\n%s see 'push.log' file for details\n" $(perror $PREFIX) $2 $(perror $PREFIX)
        return 1
    fi
}

#######################################
# Parse the options for global variables
#
# Globals:
#   DEVICE
#   SIMULATE
#   VIDEOS
#   PHOTOS
#   CAMERA
#   PULL
#   PUSH
# Arguments:
#   $@: All the arguments
# Outputs:
#   Writes to global variables
#######################################
parse_opts() {
    while [[ $# -gt 0 ]]; do
        case "$1" in 
            --usb|-u) DEVICE='-d' ;;
            --wifi|-w) DEVICE='-e' ;;
            --serial|-s) DEVICE="-s $2"; shift 1 ;;
            --simulate) SIMULATE=true ;;
            --camera|--cam|-c) CAMERA=true ;;
            --videos|-v) VIDEOS=true ;;
            --photos|-p) PHOTOS=true ;;
            --all|-a) CAMERA=true;VIDEOS=true;PHOTOS=true ;;
            --push) PUSH=true; PULL=false ;;
            --pull) PULL=true; PUSH=false ;;
            --sync) PULL=true; PUSH=true ;;
            *)
                if [[ $1 == -* ]]; then
                    printf "%s unknow option \x1b[1;96m'%s'\x1b[0m\n" $(perror $PREFIX) $1
                    exit 1
                fi

                # Stores the rest of args that are not options
                # TODO: put in use 
                ARGS+=("$1")
                ;;
        esac
        shift 1
    done
}

#######################################
# The start point of the script
#
# Arguments:
#   $@: All the arguments
#######################################
main() {
    if ! type adb > /dev/null; then
        printf "%s 'adb' not found in path" $(perror $PREFIX)
        exit 1
    fi

    parse_opts $@
    declare -p PULL PUSH

    if [ ! "$(adb $DEVICE get-state 2>/dev/null)" ]; then
        printf "%s no devices found\n" $(perror $PREFIX)
        exit 1
    fi

    if ! $CAMERA && ! $VIDEOS  && ! $PHOTOS; then
        printf "%s no directory provided, use '--cam' | '--videos' | '--photos' | '--all' (you can combine)\n" $(perror 'sync:')
        exit 1
    fi

    if $PULL; then
        if $CAMERA; then pull_files /sdcard/DCIM/Camera /hdd/media/camera; fi
        if $VIDEOS; then pull_files /sdcard/Pictures/videos /hdd/media/videos; fi
        if $PHOTOS; then pull_files /sdcard/Pictures/photos /hdd/media/photos; fi
    fi

    if $PUSH; then
        if $CAMERA; then push_files /hdd/media/camera /sdcard/DCIM/Camera; fi
        if $VIDEOS; then push_files /hdd/media/videos /sdcard/Pictures/videos; fi
        if $PHOTOS; then push_files /hdd/media/photos /sdcard/Pictures/photos; fi
    fi
}

main $@
