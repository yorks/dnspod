#!/bin/bash

# Notice: NEED TESTTING

BASEDIR="$( $(cd -P ./) && pwd )"
SCRIPTDIR="$( cd -P "$( dirname "$0" )" && pwd )"
exe=""
test -f "$BASEDIR/dnspod.sh" && exe="$BASEDIR/dnspod.sh"
test -f "$SCRIPTDIR/dnspod.sh" && exe="$SCRIPTDIR/dnspod.sh"
chmod +x "$exe"

echo "arg1 $1"
echo "arg2 $2"
echo "arg3 $3"
echo "arg4 $4"

TTL=600
case "$1" in
    "deploy_challenge")
        printf "update add _acme-challenge.%s. %d in TXT \"%s\"\n\n" "${2}" "${TTL}" "${4}"
        $exe update $2 _acme-challenge.  "$4" TXT | tail -n 1 | grep -q failed && { echo "update failed, pls update it by hand."; read; }
        sleep $TTL
        ;;
    "clean_challenge")
        printf "delete _acme-challenge.%s. %d in TXT \"%s\"\n\n" "${2}" "${TTL}" "${4}"
        $exe delete $2 _acme-challenge.  | tail -n 1 | grep -q failed && { echo "deleted failed, pls update it by hand.";  }
        sleep $TTL
        ;;
    "deploy_cert")
        # TODO
        ;;
    "unchanged_cert")
        # TODO
        echo unchanged_cert
        ;;
    *)  
        echo Unkown hook "${1}"
        exit 1
        ;;
esac
