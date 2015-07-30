#!/bin/bash

[ -z "${AUTHZFORCE_HOSTNAME}" ] && echo "AUTHZFORCE_HOSTNAME is undefined.  Using default value of 'authzforce'" && export AUTHZFORCE_HOSTNAME=authzforce
[ -z "${AUTHZFORCE_PORT}" ] && echo "AUTHZFORCE_PORT is undefined.  Using default value of '8080'" && export AUTHZFORCE_PORT=8080
[ -z "${IDM_KEYROCK_HOSTNAME}" ] && echo "IDM_KEYROCK_HOSTNAME is undefined.  Using default value of 'idm'" && export IDM_KEYROCK_HOSTNAME=idm
[ -z "${IDM_KEYROCK_PORT}" ] && echo "IDM_KEYROCK_PORT is undefined.  Using default value of '443'" && export IDM_KEYROCK_PORT=443
[ -z "${MAGIC_KEY}" ] && echo "MAGIC_KEY is undefined. Using default value of 'daf26216c5434a0a80f392ed9165b3b4'" && export MAGIC_KEY=daf26216c5434a0a80f392ed9165b3b4
[ -z "${WORKON_HOME}" ] && echo "WORKON_HOME is undefined.  Using default value of '/opt/virtualenvs'" && export WORKON_HOME=/opt/virtualenvs
[ -z "${APP_NAME}" ] && echo "APP_NAME is undefined.  Using default value of 'FIWAREdevGuide'" && export APP_NAME="FIWAREdevGuide"
[ -z "${CONFIG_FILE}" ] && echo "CONFIG_FILE is undefined.  Using default value of '/config/idm2chanchan.json'" && export CONFIG_FILE=/config/idm2chanchan.json
[ -z "${PROVISION_FILE}" ] && echo "PROVISION_FILE is undefined.  Using default value of '/config/keystone_provision.py'" && export PROVISION_FILE=/config/keystone_provision.py
[ -z "${DEFAULT_MAX_TRIES}" ] && echo "DEFAULT_MAX_TRIES is undefined.  Using default value of '30'" && export DEFAULT_MAX_TRIES=30

declare DOMAIN=''

# fix variables when using docker-compose
if [[ ${AUTHZFORCE_PORT} =~ ^tcp://[^:]+:(.*)$ ]] ; then
    export AUTHZFORCE_PORT=${BASH_REMATCH[1]}
fi

function check_host_port () {

    local _timeout=10
    local _tries=0
    local _is_open=0

    if [ $# -lt 2 ] ; then
	echo "check_host_port: missing parameters."
	echo "Usage: check_host_port <host> <port> [max-tries]"
	exit 1
    fi

    local _host=$1
    local _port=$2
    local _max_tries=${3:-${DEFAULT_MAX_TRIES}}
    local NC=$( which nc )

    if [ ! -e "${NC}" ] ; then
	echo "Unable to find 'nc' command."
	exit 1
    fi

    echo "Testing if port '${_port}' is open at host '${_host}'."

    while [ ${_tries} -lt ${_max_tries} -a ${_is_open} -eq 0 ] ; do
	echo -n "Checking connection to '${_host}:${_port}' [try $(( ${_tries} + 1 ))/${_max_tries}] ... "
	if ${NC} -z -w ${_timeout} ${_host} ${_port} ; then
	    echo "OK."
	    _is_open=1
	else
	    echo "Failed."
	    sleep 1
	    _tries=$(( ${_tries} + 1 ))
	fi
    done

    if [ ${_is_open} -eq 0 ] ; then
	echo "Failed to connect to port '${_port}' on host '${_host}' after ${_tries} tries."
	echo "Port is closed or host is unreachable."
	exit 1
    else
	echo "Port '${_port}' at host '${_host}' is open."
    fi
}


function check_domain () {

	if [ $# -lt 2 ] ; then
	echo "check_host_port: missing parameters."
	echo "Usage: check_host_port <host> <port> [max-tries]"
	exit 1
    fi

	local _host=$1
    local _port=$2

	# Request to Authzforce to retrieve Domain

	DOMAIN="$(curl -s --request GET http://${_host}:${_port}/authzforce/domains | awk '/href/{print $NF}' | cut -d '"' -f2)" 

	# Checks if the Domain exists. If not, creates one

	if [ -z "$DOMAIN" ]; then 
	    echo "Domain is not created yet!"
	    curl -s --request POST --header "Content-Type: application/xml;charset=UTF-8" --data '<?xml version="1.0" encoding="UTF-8"?><taz:properties xmlns:taz="http://thalesgroup.com/authz/model/3.0/resource"><name>MyDomain</name><description>This is my domain.</description></taz:properties>' --header "Accept: application/xml" http://${_host}:${_port}/authzforce/domains --output /dev/null
	    DOMAIN="$(curl -s --request GET http://${_host}:${_port}/authzforce/domains | awk '/href/{print $NF}' | cut -d '"' -f2)"
	    echo "Domain has been created: $DOMAIN"
	else
	    echo "Domain value is not empty: "
	    echo $DOMAIN
	fi

}

function check_file () {

    local _tries=0
    local _is_available=0

    local _file=$1
    local _max_tries=${3:-${DEFAULT_MAX_TRIES}}

    echo "Testing if file '${_file}' is available."

    while [ ${_tries} -lt ${_max_tries} -a ${_is_available} -eq 0 ] ; do
    echo -n "Checking file '${_file}' [try $(( ${_tries} + 1 ))/${_max_tries}] ... "
    if [ -r ${_file} ] ; then
        echo "OK."
        _is_available=1
    else
        echo "Failed."
        sleep 1
        _tries=$(( ${_tries} + 1 ))
    fi
    done

    if [ ${_is_available} -eq 0 ] ; then
    echo "Failed to to retrieve '${_file}' after ${_tries} tries."
    echo "File is unavailable."
    exit 1
    else
    echo "File '${_file}' is available."
    fi
}

function _data_provision () {

    sed -i '/from deployment import keystone/a from deployment import keystone_provision' /opt/fi-ware-idm/fabfile.py
    cp ${PROVISION_FILE} /opt/fi-ware-idm/deployment/keystone_provision.py
	source /usr/share/virtualenvwrapper/virtualenvwrapper.sh
    workon idm_tools
    echo "Lauching dev_server"
    (fab localhost keystone.dev_server &)
    sleep 10
    echo "Providing the roles"
    fab localhost keystone_provision.test_data
    echo "Provision done. Killing process"
    (ps axf | grep -i keystone-all | grep -v grep | sed -e 's/^ *//g' | cut -d ' ' -f 1 | xargs kill -s TERM)

}

function _config_file () {

	echo "Parsing App information into a JSON file"
	source /opt/fi-ware-idm/keystone/.venv/bin/activate
	python /opt/fi-ware-idm/keystone/chanchan-config.py --name ${APP_NAME} --file ${CONFIG_FILE}
}

# Call checks

check_host_port ${AUTHZFORCE_HOSTNAME} ${AUTHZFORCE_PORT}
check_domain ${AUTHZFORCE_HOSTNAME} ${AUTHZFORCE_PORT}
check_file ${PROVISION_FILE}
_data_provision
_config_file

# Parse the value into the IdM settings

sed -e "s@^ACCESS_CONTROL_URL = None@ACCESS_CONTROL_URL = 'http://${AUTHZFORCE_HOSTNAME}:${AUTHZFORCE_PORT}/authzforce/domains/${DOMAIN}/pap/policySet'@" -i /opt/fi-ware-idm/horizon/openstack_dashboard/local/local_settings.py
sed -e "s@^ACCESS_CONTROL_MAGIC_KEY = None@ACCESS_CONTROL_MAGIC_KEY = '${MAGIC_KEY}'@" -i /opt/fi-ware-idm/horizon/openstack_dashboard/local/local_settings.py

# Parse value into apache configuration

sed -i /etc/apache2/sites-available/idm.conf \
    -e "s|IDM_KEYROCK_HOSTNAME|${IDM_KEYROCK_HOSTNAME}|g"

# Start container back

exec /sbin/init
