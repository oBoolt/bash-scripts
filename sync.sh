# sync.sh <--usb | --wifi | --serial <SERIAL_NUMBER>> <--copy | --delete | --action [copy | delete]> <--local | --remote | --sync (only for copy action)> [--config <PATH>] 
#######################################
# Globals
#######################################
PREFIX='sync:'
DEVICE='-d'
REMOTE=true
LOCAL=false
CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/scripts/sync.conf"
SIMULATE=false

CAMERA=false
CAMERA_PATH=
VIDEOS=false
VIDEOS_PATH=
PHOTOS=false
PHOTOS_PATH=
CUSTOM=false
# Use declare with '-A' option to create an associative array
declare -A CUSTOM_PATHS

ACTION=1 # 1=copy 2=delete


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
# Parse the options for global variables
#
# Globals:
#   DEVICE
#   SIMULATE
#   VIDEOS
#   PHOTOS
#   CAMERA
#   LOCAL
#   REMOTE
#   CONFIG_PATH
#   ACTION
# Arguments:
#   $@: All the arguments
# Outputs:
#   Writes to global variables
#######################################
parse_opts() {
    local PREFIX='parse_opts:'
    while [[ $# -gt 0 ]]; do
        case "$1" in 
            --usb|-u) DEVICE='-d' ;;
            --wifi|-w) DEVICE='-e' ;;
            --serial|-s) DEVICE="-s $2"; shift 1 ;;
            --simulate) SIMULATE=true ;;
            --camera|--cam|-c) CAMERA=true ;;
            --videos|-v) VIDEOS=true ;;
            --photos|-p) PHOTOS=true ;;
            --custom) CUSTOM=true ;;
            --all|-a) CAMERA=true;VIDEOS=true;PHOTOS=true; CUSTOM=true ;;
            --local) LOCAL=true; REMOTE=false ;;
            --remote) REMOTE=true; LOCAL=false ;;
            --sync) REMOTE=true; LOCAL=true ;;
            --config) CONFIG_PATH="$2"; shift 1 ;;
            --action)
                case ${2,,} in
                    copy) ACTION=1 ;;
                    delete) ACTION=2 ;;
                    *)
                        printf "%s unknow action \x1b[1;96m'%s'\x1b[0m\n" $(perror $PREFIX) $2
                        exit 1
                        ;;

                    esac
                    shift 1
                    ;;
                *)
                    if [[ $1 == -* ]]; then
                        printf "%s unknow option \x1b[1;96m'%s'\x1b[0m\n" $(perror $PREFIX) $1
                        exit 1
                    fi
                    ;;
            esac
            shift 1
        done
    }

#######################################
# Parse the config file
#
# Globals:
#   PREFIX
#   CONFIG_PATH
#   CAMERA_PATH
#   VIDEOS_PATH 
#   PHOTOS_PATH
#   CUSTOM_PATHS
# Outputs:
#   Writes an array of paths separeted by
#   an '=' sign, where the first element
#   is the LOCAL path and the second is 
#   the REMOTE paht
#######################################
parse_config() {
    local PREFIX='parse_config:'
    if ! [ -r $CONFIG_PATH ]; then
        printf "%s cannot access \x1b[1;96m'%s'\x1b[0m: no such file\n" $(perror $PREFIX) $CONFIG_PATH
        exit 1
    fi

    while IFS='\n' read -r line;
    do
        if [[ $line == '#'* ]]; then continue; fi
        shopt -s extglob       
        case $line in
            camera:*)
                IFS='=' read -a line_split <<< "$line"
                CAMERA_PATH[0]=${line_split[0]##camera:}
                CAMERA_PATH[1]=${line_split[1]}
                ;;
            videos:*) 
                IFS='=' read -a line_split <<< "$line"
                VIDEOS_PATH[0]=${line_split[0]##videos:}
                VIDEOS_PATH[1]=${line_split[1]}
                ;;
            photos:*)
                IFS='=' read -a line_split <<< "$line"
                PHOTOS_PATH[0]=${line_split[0]##photos:}
                PHOTOS_PATH[1]=${line_split[1]}
                ;; 
            custom:*)
                IFS='=' read -a line_split <<< "$line"
                CUSTOM_PATHS+=(["${line_split[0]##custom:}"]="${line_split[1]}")
                ;;
        esac
        shopt -u extglob       
    done < "$CONFIG_PATH"
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
    local PREFIX='pull:'
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

    [[ $SIMULATE == false ]] && $(adb $DEVICE pull ${files[*]} "$2/" 2>>"$2/../pull.log")

    if ! $SIMULATE  && [ $? -eq 0 ]; then
        printf "%s success pulling file(s) from \x1b[1;36m'%s'\x1b[0m to \x1b[1;36m'%s'\x1b[0m\n" $(psuccess $PREFIX) $1 $2
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
    local PREFIX='push:'
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
        $(adb $DEVICE push ${files[*]} "$2" 2>>"$1/../push.log")
    fi

    if ! $SIMULATE && [ $? -eq 0 ]; then
        printf "%s success pushing file(s) from \x1b[1;36m'%s'\x1b[0m to \x1b[1;36m'%s'\x1b[0m\n" $(psuccess $PREFIX) $1 $2
        return 0
    fi

    if [ $? -eq 1 ]; then
        printf "%s failed to push file(s) to \x1b[1;36m'%s'\x1b[0m\n%s see 'push.log' file for details\n" $(perror $PREFIX) $2 $(perror $PREFIX)
        return 1
    fi
}



#######################################
# Handles when ACTION=1
#
# Globals:
#   REMOTE
#   LOCAL
#   CAMERA
#   VIDEOS
#   PHOTOS
#   CUSTOM
#   CAMERA_PATH
#   VIDEOS_PATH
#   PHOTOS_PATH
#   CUSTOM_PATHS
#######################################
handle_copy() {
    if $REMOTE; then
        if [ -n "$CAMERA_PATH" ] && $CAMERA; then pull_files ${CAMERA_PATH[1]} ${CAMERA_PATH[0]}; fi
        if [ -n "$VIDEOS_PATH" ] && $VIDEOS; then pull_files ${VIDEOS_PATH[1]} ${VIDEOS_PATH[0]}; fi
        if [ -n "$PHOTOS_PATH" ] && $PHOTOS; then pull_files ${PHOTOS_PATH[1]} ${PHOTOS_PATH[0]}; fi
        if [[ "${#CUSTOM_PATHS[@]}" != 0 ]] && $CUSTOM; then
            for local_path in ${!CUSTOM_PATHS[@]}
            do
                remote_path="${CUSTOM_PATHS[${local_path}]}"
                pull_files $remote_path $local_path
            done
        fi
    fi

    if $LOCAL; then
        if [ -n "$CAMERA_PATH" ] && $CAMERA; then push_files ${CAMERA_PATH[0]} ${CAMERA_PATH[1]}; fi
        if [ -n "$VIDEOS_PATH" ] && $VIDEOS; then push_files ${VIDEOS_PATH[0]} ${VIDEOS_PATH[1]}; fi
        if [ -n "$PHOTOS_PATH" ] && $PHOTOS; then push_files ${PHOTOS_PATH[0]} ${PHOTOS_PATH[1]}; fi
        if [[ "${#CUSTOM_PATHS[@]}" != 0 ]] && $CUSTOM; then
            for local_path in ${!CUSTOM_PATHS[@]}
            do
                remote_path="${CUSTOM_PATHS[${local_path}]}"
                push_files $local_path $remote_path
            done
        fi
    fi
}

#######################################
# Remote files from a path
# Globals:
#   PREFIX
#   LOCAL
#   DEVICE
# Arguments:
#   $1: Path; to LOCAL files
#   $2: Path; to REMOTE files
#######################################
remove_files() {
    local PREFIX='delete:'
    files=()
    media_files="$(get_diff $2 $1 $LOCAL)"
    delete_path=$2
    [ $LOCAL = true ] && delete_path=$1
    
    if [[ -z $media_files ]]; then
        printf "%s no file(s) to delete from \x1b[1;36m'%s/'\x1b[0m\n" $(pwarn $PREFIX) $delete_path
        return 0
    fi

    IFS=$'\n' read -d "" -ra unformated_files <<< "$media_files"
    for media in "${unformated_files[@]}"
    do
        files+=("$delete_path/$media") 
    done
    printf "%s file(s) to delete from \x1b[1;36m'%s/'\x1b[0m:\n" $(pinfo $PREFIX) $delete_path
    printf "\x1b[34m%s\x1b[0m\n" "${media_files[@]}"

    if ! $SIMULATE; then
        read -p "Are you sure? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]
        then
            [[ "$0" = "$BASH_SOURCE" ]] && exit 0 || return 0 
        fi

        if $LOCAL; then
            rm ${files[*]} >>"$1/../delete.log"
        fi
        $(adb $DEVICE shell "rm ${files[*]}" 2>>"$1/../delete.log")
    fi
}

#######################################
# Handles when ACTION=2
#
# Globals:
#   REMOTE
#   LOCAL
#   CAMERA
#   VIDEOS
#   PHOTOS
#   CUSTOM
#   CAMERA_PATH
#   VIDEOS_PATH
#   PHOTOS_PATH
#   CUSTOM_PATHS
# Arguments:
#   $1: Path; to LOCAL files
#   $2: Path; to REMOTE files
#######################################
handle_delete() {
    if [ -n "$CAMERA_PATH" ] && $CAMERA; then remove_files ${CAMERA_PATH[0]} ${CAMERA_PATH[1]}; fi
    if [ -n "$VIDEOS_PATH" ] && $VIDEOS; then remove_files ${VIDEOS_PATH[0]} ${VIDEOS_PATH[1]}; fi
    if [ -n "$PHOTOS_PATH" ] && $PHOTOS; then remove_files ${PHOTOS_PATH[0]} ${PHOTOS_PATH[1]}; fi
    if [[ "${#CUSTOM_PATHS[@]}" != 0 ]] && $CUSTOM; then
        for local_path in ${!CUSTOM_PATHS[@]}
        do
            remote_path="${CUSTOM_PATHS[${local_path}]}"
            remove_files $local_path $remote_path
        done
    fi
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
    parse_config

    if [ ! "$(adb $DEVICE get-state 2>/dev/null)" ]; then
        printf "%s no devices found\n" $(perror $PREFIX)
        exit 1
    fi

    if [ -z "$CAMERA_PATH" ] && [ -z "$VIDEOS_PATH" ] && [ -z "$PHOTOS_PATH" ]; then
        printf "%s no path found in config, use the '--config <path_to_config>' option or create the file '$HOME/.config/scripts/sync.conf'\n" $(perror $PREFIX)
        exit 1
    fi

    if ! $CAMERA && ! $VIDEOS  && ! $PHOTOS && ! $CUSTOM; then
        printf "%s no directory provided, use '--cam' | '--videos' | '--photos' | '--custom' | '--all' (you can combine)\n" $(perror $PREFIX)
        exit 1
    fi

    case $ACTION in 
        1) handle_copy ;;
        2) handle_delete ;;
        *) 
            printf "%s action cannot be handled\n" $(perror $PREFIX)
            exit 1
            ;;
    esac

}

main $@
