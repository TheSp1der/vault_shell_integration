#! /usr/bin/env sh

# Original Concept by: pezhore (https://gist.github.com/pezhore)
# https://gist.github.com/pezhore/209a769920b917de191822ae8bee8984

# Copyright 2021 The_Spider (https://github.com/TheSp1der)
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set_defaults() {
	SELF="$(basename "${0}")"

	VAULT_API_HOST="example.com"
	VAULT_API_PORT="443"
	VAULT_LOGIN_TYPE="user"
}

check_required_programs() {
	if ! curl --version > /dev/null 2>&1; then
		printf 'Unable to locate required program: %s\n' "curl"
		exit 10
	fi
	if ! jq --version > /dev/null 2>&1; then
		printf 'Unable to locate required program: %s\n' "jq"
		exit 10
	fi
	if ! sed --version > /dev/null 2>&1; then
		printf 'Unable to locate required program: %s\n' "sed"
		exit 10
	fi
}

check_required_paremeters() {
	if [ -z ${VAULT_USERNAME+x} ]; then
		printf 'Vault username is undefined\n%s\n' "--"
		printHelp
		exit 20
	fi
	if [ -z ${VAULT_PASSWORD+x} ]; then
		printf 'Vault password is undefined\n%s\n' "--"
		printHelp
		exit 20
	fi
	if [ -z ${VAULT_LOGIN_TYPE+x} ]; then
		printf 'Vault password is undefined\n%s\n' "--"
		printHelp
		exit 20
	fi
	if [ "${VAULT_LOGIN_TYPE}" != "ldap" ] && [ "${VAULT_LOGIN_TYPE}" != "user" ]; then
		printf 'Login method must be one of ldap or user: \n%s\n' "--"
		printHelp
		exit 20
	fi
	if [ -z ${VAULT_SECRET_STORE+x} ]; then
		printf 'Vault secret store is undefined\n%s\n' "--"
		printHelp
		exit 20
	fi
	if [ -z ${VAULT_SECRET_PATH+x} ]; then
		printf 'Vault secret path is undefined\n%s\n' "--"
		printHelp
		exit 20
	fi
}

revoke_token() {
	curl --request POST \
		--silent \
		--location \
		--header "$(printf 'X-Vault-Token: %s' "${VAULT_TOKEN}" )" \
		"https://${VAULT_API_HOST}:${VAULT_API_PORT}/v1/auth/token/revoke-self"
	unset TOKEN
}

printHelp() {
	printf '%s - %s\n' "${SELF}" "Vault shell integration script."
	printf '%s\n' "Integrates environment variables from your local vault instance."
	printf 'Usage: source %s [options...]\n' "${SELF}"
	printf '%s, %s <%s>\t\t%s\n' "-H" "--host" "hostname" "Vault api hostname (example.com)"
	printf '%s, %s <%s>\t\t%s\n' "-P" "--port" "port" "Vault api port (443)"
	printf '%s, %s (%s)\t%s\n' "-l" "--login-method" "ldap|user" "Vault login method (user)"
	printf '%s, %s <%s>\t\t%s\n' "-u" "--user" "user name" "*REQUIRED* Vault username"
	printf '%s, %s <%s>\t\t%s\n' "-p" "--pass" "password" "*REQUIRED* Vault password"
	printf '%s, %s <%s>\t%s\n' "-s" "--store" "secret store" "*REQUIRED* Vault secret store"
	printf '%s, %s <%s>\t%s\n' "-t" "--path" "secret path" "*REQUIRED* Vault secret path"
}

do_get_token() {
	if [ "${VAULT_LOGIN_TYPE}" = "user" ]; then
		DATA="$(curl --request POST \
			--silent \
			--location \
			--data "$(printf '{ "password": "%s" }' "${VAULT_PASSWORD}" )" \
			"https://${VAULT_API_HOST}:${VAULT_API_PORT}/v1/auth/userpass/login/${VAULT_USERNAME}")"
	else
		DATA="$(curl --request POST \
			--silent \
			--location \
			--data "$(printf '{ "password": "%s" }' "${VAULT_PASSWORD}" )" \
			"https://${VAULT_API_HOST}:${VAULT_API_PORT}/v1/auth/ldap/login/${VAULT_USERNAME}")"
	fi

	ERROR="$(printf '%s' "${DATA}" | jq -r '.errors[0]')"
	if [ -z ${ERROR+x} ] || [ "${ERROR}" != "null" ]; then
		printf 'Unable to login to vault: %s\n' "${ERROR}"
		revoke_token
		exit 30
	fi

	VAULT_TOKEN="$(printf '%s' "${DATA}" | jq -r '.auth.client_token')"
	if [ -z ${VAULT_TOKEN+x} ] || [ "${VAULT_TOKEN}" = "null" ]; then
		printf 'Unable to get token from vault api\n'
		revoke_token
		exit 30
	fi

	unset DATA ERROR
}

get_secrets() {
	DATA="$(curl --request GET \
		--silent \
		--location \
		--header "$(printf 'X-Vault-Token: %s' "${VAULT_TOKEN}" )" \
		"https://${VAULT_API_HOST}:${VAULT_API_PORT}/v1/${VAULT_SECRET_STORE}/data/${VAULT_SECRET_PATH}")"

	ERROR="$(printf '%s' "${DATA}" | jq -r '.errors[0]')"
	if [ -z ${ERROR+x} ] || [ "${ERROR}" != "null" ]; then
		printf 'Unable to retrieve secret(s): %s\n' "${ERROR}"
		revoke_token
		exit 40
	fi

	SECRETS="$(printf '%s' "${DATA}" | jq -r '.data.data | to_entries | .[] | .key + "=" + .value')"
	if [ -z ${SECRETS+x} ] || [ "${SECRETS}" = "null" ]; then
		printf 'Unable to retrieve secret(s): %s\n' "Secret is empty"
		revoke_token
		exit 40
	fi

	unset DATA ERROR
}

set_environment_variables() {
	DATA=$(printf '%s' "${SECRETS}" | sed -e ':a' -e 's/^\([^=]*\)-/\1_/;t a')
	
	eval "$(printf 'IFS="\n"')"
	for i in ${DATA}; do
		export "${i}"
	done
	unset SECRETS
}

# main process
set_defaults
check_required_programs

if [ ${#} -eq 0 ]; then
	printf 'Invalid Usage: Must supply optional parameters\n%s\n' "--"
	printHelp
	exit 100
fi

while [ "${#}" -gt 0 ]; do
	case ${1} in
		-D | --debug )
			set -x
			shift
		;;
		-H | --host )
			VAULT_API_HOST="${2}"
			shift
			shift
		;;
		-P | --port )
			VAULT_API_PORT="${2}"
			shift
			shift
		;;
		-l | --login-method )
			VAULT_LOGIN_TYPE="${2}"
			shift
			shift
		;;
		-u | --user )
			VAULT_USERNAME="${2}"
			shift
			shift
		;;
		-p | --pass )
			VAULT_PASSWORD="${2}"
			shift
			shift
		;;
		-s | --store )
			VAULT_SECRET_STORE="${2}"
			shift
			shift
		;;
		-t | --path )
			VAULT_SECRET_PATH="${2}"
			shift
			shift
		;;
		*)
			printf 'Invalid Parmeter Specified: %s\n%s\n' "${1}" "--"
			printHelp
			exit 100
		;;
	esac
done

check_required_paremeters
do_get_token
get_secrets
set_environment_variables
revoke_token
