# ansi escapes for hilighting text
F_DANGER=$(echo -e "\033[31m")
F_WARN=$(echo -e "\033[93m")
F_RESET=$(echo -e "\033[39m")


danger() {
    local echoarg
    case "$1" in
        -n )
            echoarg="$1"
            shift
            ;;
        * )
            echoarg=""
    esac
    echo $echoarg "${F_DANGER}$1${F_RESET}"
}

warn() {
    local echoarg
    case "$1" in
        -n )
            echoarg="$1"
            shift
            ;;
        * )
            echoarg=""
    esac
    echo "${F_WARN}$1${F_RESET}"
}

