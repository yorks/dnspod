#!/bin/bash

# CONST VARS
__VERSION__="0.0.1"
__AUTH__="stuyorks@gmail.com"

DNSPOD_API_PRE="https://dnsapi.cn/"
ARCH=$(uname -m)
# https://www.dnspod.cn/docs/info.html
UA="DNSPOD API Bash Client ${ARCH}/${__VERSION__} (${__AUTH__})"
BASEDIR="$( $(cd -P ./) && pwd )"
SCRIPTDIR="$( cd -P "$( dirname "$0" )" && pwd )"

# Print error message and exit with error
_exiterr() {
  echo "ERROR: ${1}" >&2
  exit 1
}


# Get string value from json dictionary
get_json_string_value() {
  grep -Eo '"'"${1}"'":[[:space:]]*"[^"]*"' | cut -d'"' -f4
}

# Send http(s) request with specified method
# copy from letsencryt.sh
http_request() {
  tempcont="$(mktemp -t XXXXXX)"

  set +e
  if [[ "${1}" = "head" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -I)"
    curlret="${?}"
  elif [[ "${1}" = "get" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}")"
    curlret="${?}"
  elif [[ "${1}" = "post" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -d "${3}")"
    curlret="${?}"
  else
    set -e
    _exiterr "Unknown request method: ${1}"
  fi
  set -e

  if [[ ! "${curlret}" = "0" ]]; then
    test -f "${tempcont}" && rm -f "${tempcont}"
    _exiterr "Problem connecting to server (curl returned with ${curlret})"
  fi

  if [[ ! "${statuscode:0:1}" = "2" ]]; then
    echo "  + ERROR: An error occurred while sending ${1}-request to ${2} (Status ${statuscode})" >&2
    echo >&2
    echo "Details:" >&2
    cat "${tempcont}" >&2
    rm -f "${tempcont}"

    exit 1
  fi

  cat "${tempcont}"
  rm -f "${tempcont}"
}

# Send api request
api_request() {
  # $1 path, $2 post_data
  url="${DNSPOD_API_PRE}${1}"
  
  http_request post "${url}" "login_token=${LOGIN_TK}&format=json&${2}"
}

get_domain_list(){
  path='Domain.List'
  api_request "$path" ''
}

get_domain_info(){
  path='Domain.Info'
  args="domain=${1}"
  api_request "$path" "${args}"
}

get_domain_record_list(){
  path='Record.List'
  args="domain_id=${1}"
  [[ -z  "${2}" ]] || args="${args}&sub_domain=${2}"
  api_request "$path" "${args}"
}

add_domain_record(){
  path='Record.Create'
  args="domain_id=${1}&sub_domain=${2}&record_type=${3}&record_line=默认&value=${4}"
  [[ -z "${4}" ]] && _exiterr "Missing record value"
  echo "${3}" | egrep -q "^(A|TXT)$" || _exiterr "Missing record type or unkonwn record type, sopport: A or TXT only."
  api_request "$path" "${args}"
}
set_domain_record(){
  path='Record.Modify'
  args="domain_id=${1}&record_id=${2}&sub_domain=${3}&record_type=${4}&record_line=默认&value=${5}"
  [[ -z "${5}" ]] && _exiterr "Missing record value"
  echo "${4}" | egrep -q "^(A|TXT)$" || _exiterr "Missing record type or unkonwn record type, sopport: A or TXT only."
  api_request "$path" "${args}"
}
del_domain_record(){
  path='Record.Remove'
  args="domain_id=${1}&record_id=${2}"
  [[ -z "${2}" ]] && _exiterr "Missing record_id"
  api_request "$path" "${args}"
  
}

# Check for script dependencies
check_dependencies() {
  # just execute some dummy and/or version commands to see if required tools exist and are actually usable
  #openssl version > /dev/null 2>&1 || _exiterr "This script requires an openssl binary."
  sed "" < /dev/null > /dev/null 2>&1 || _exiterr "This script requires sed with support for extended (modern) regular expressions."
  grep -V > /dev/null 2>&1 || _exiterr "This script requires grep."
  mktemp -u -t XXXXXX > /dev/null 2>&1 || _exiterr "This script requires mktemp."

  # curl returns with an error code in some ancient versions so we have to catch that
  set +e
  curl -V > /dev/null 2>&1
  retcode="$?"
  set -e
  if [[ ! "${retcode}" = "0" ]] && [[ ! "${retcode}" = "2" ]]; then
    _exiterr "This script requires curl."
  fi
}

load_cf(){
    CFS="/etc/dnspod.ini /opt/etc/dnspod.ini /tmp/dnspod.ini ${SCRIPTDIR}/dnspod.ini ${BASEDIR}/dnspod.ini"
    for cf in ${CFS}; do
        test -f ${cf} && . ${cf} && break
    done
    if [[ -z "${LOGIN_TK}" ]];then
        test -f ${cf}  || _exiterr "Missing LOGIN_TK value you can configure it by export LOGIN_TK=?? or place to configure file which must place to: /etc/dnspod.ini | /opt/etc/dnspod.ini | /tmp/dnspod.ini ${SCRIPTDIR}/dnspod.ini ${BASEDIR}/dnspod.ini"
    fi
    [[ -z "${LOGIN_TK}" ]] && _exiterr "Missing LOGIN_TK  in cf"
    echo ${LOGIN_TK} | grep -q ','  || _exiterr  "Bad LOGIN_TK formart, Must like this: ID,Token"
}

check_ok(){
    ret=$1
        code=$(echo "${ret}" | get_json_string_value code) 
        [[ "x$code" != "x1" ]] && {
           echo $ret
           echo 
           echo "failed"
           return 1
        } || echo ok
}

# Main method (parses script arguments and calls command_* methods)
main() {
    echo 
}

add_sub_record_value()
{
    domain=$1
    sub=$2
    value=$3
    rtype=$4
    [[ "x$rtype" == "x" ]] && rtype="A"
    domain_info=$(get_domain_info ${domain})
    domain_id=$(echo ${domain_info}|get_json_string_value id) 
    [[ "x$domain_id" == "x" ]] && {
        echo "Maybe domain not exist?"
        echo "Cannot found the domain_id from the domain info from api:"
        echo $domain_info
        echo 
        echo "failed"
        return 1
    }

    echo "adding the new record $sub.$domain $rtype"
    addinfo=$(add_domain_record $domain_id $sub $rtype  $value)
    check_ok "${addinfo}"
    return 0
}

get_sub_record_value()
{
    domain=$1
    sub=$2
    rtype=$3
    [[ "x$rtype" == "x" ]] && rtype="A"
    domain_info=$(get_domain_info ${domain})
    domain_id=$(echo ${domain_info}|get_json_string_value id) 
    [[ "x$domain_id" == "x" ]] && {
        echo "Maybe domain not exist?"
        echo "Cannot found the domain_id from the domain info from api:"
        echo $domain_info
        echo 
        echo "failed"
        return 1
    }

    record=$(get_domain_record_list "${domain_id}" $sub)
    code=$(echo "${record}" | get_json_string_value code)

    if [[ "x$code" != "x1" ]]; then 
        echo "record not exist. $sub.$domain $rtype"
        echo "failed"
        return 1
    else
        rid=$(echo "${record}" | get_json_string_value id)
        oldvalue=$(echo "${record}" | get_json_string_value value)
        echo "$sub.$domain $rtype record_id:$rid value:$oldvalue"
        return 0
    fi

}

 

add_or_update_sub_record_value()
{
    domain=$1
    sub=$2
    value=$3
    rtype=$4
    [[ "x$rtype" == "x" ]] && rtype="A"
    domain_info=$(get_domain_info ${domain})
    domain_id=$(echo ${domain_info}|get_json_string_value id) 
    [[ "x$domain_id" == "x" ]] && {
        echo "Maybe domain not exist?"
        echo "Cannot found the domain_id from the domain info from api:"
        echo $domain_info
        echo 
        echo "failed"
        return 1
    }

    record=$(get_domain_record_list "${domain_id}" $sub)
    code=$(echo "${record}" | get_json_string_value code)

    if [[ "x$code" != "x1" ]]; then 
        echo $record
        echo "adding the new record $sub.$domain TXT"
        addinfo=$(add_domain_record $domain_id $sub $rtype  $value)
        check_ok "${addinfo}"
        return 0
    else
        echo "recored $sub.$domain $rtype is already exist, new update it."
        rid=$(echo "${record}" | get_json_string_value id)
        oldvalue=$(echo "${record}" | get_json_string_value value)
        echo "record_id:$rid oldvalue:$oldvalue newvalue:$value"
        #echo "y|n:"
        #read
        setinfo=$(set_domain_record $domain_id $rid $sub $rtype  $value)
        check_ok "${setinfo}"
        return 0
    fi

}


del_sub_record_value()
{
    domain=$1
    sub=$2
    domain_info=$(get_domain_info ${domain})
    domain_id=$(echo ${domain_info}|get_json_string_value id) 
    [[ "x$domain_id" == "x" ]] && {
        echo "Maybe domain not exist?"
        echo "Cannot found the domain_id from the domain info from api:"
        echo $domain_info
        echo 
        echo "failed"
        return 1
    }

    record=$(get_domain_record_list "${domain_id}" $sub)
    code=$(echo "${record}" | get_json_string_value code)

    if [[ "x$code" != "x1" ]]; then 
        echo $record
        echo "record $sub.$domain not found"
        echo "failed"
        return 0
    else
        echo "recored $sub.$domain $rtype is already exist, new delete it."
        rid=$(echo "${record}" | get_json_string_value id)
        oldvalue=$(echo "${record}" | get_json_string_value value)
        echo "deleting $sub.$domain, record_id:$rid oldvalue:$oldvalue "
        delinfo=$(del_domain_record $domain_id $rid)
        check_ok "${delinfo}"
        return 0
    fi
}




# Run script
# Check for missing dependencies
check_dependencies
load_cf
#get_domain_list | get_json_string_value name
case "$1" in
    "get_domain_list")
        get_domain_list | get_json_string_value name
        ;;
    "get_domain_info")
        get_domain_info $2
        ;;
    "get_sub_info")
        get_sub_record_value $2 $3 $4
        ;;
    "update")
        add_or_update_sub_record_value $2 $3 $4 $5
        ;;
    "add")
        add_sub_record_value $2 $3 $4 $5
        ;;
    "delete")
        del_sub_record_value $2 $3
        ;;
    *)  
        echo "Unkown cmd ${1}"
        exit 1
        ;;
esac
