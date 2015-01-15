#!/bin/bash
##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
#
#    Contributers:
#     * dalgibbard - http://github.com/dalgibbard
#     * epos-eu    - http://github.com/epos-eu
##

## This script outputs the content of a couchdb database to a file,
## in a format that can be later uploaded with the bulk docs directive

## USAGE
## ** example: ./couchdb-dump.sh -H 127.0.0.1 -d mydb -u admin -p password -f mydb.json

###################### CODE STARTS HERE ###################

##START: FUNCTIONS
usage(){
	echo
	echo "Usage: $0 -H <COUCHDB_HOST> -d <DB_NAME> -f <OUTPUT_FILE> [-u <username>] [-p <password>] [-P <port>]"
	echo -e "\t-h   Display usage information."
	echo -e "\t-H   CouchDB URL. Can be provided with or without 'http://'"
	echo -e "\t-d   CouchDB Database name to dump."
	echo -e "\t-f   File to write Database to."
	echo -e "\t-P   Provide a port number for CouchDB [Default: 5984]"
	echo -e "\t-u   Provide a username for auth against CouchDB [Default: blank]"
	echo -e "\t-p   Provide a password for auth against CouchDB [Default: blank]"
	echo
	echo "Example: $0 ./couchdb-dump.sh -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password"
	echo
	exit 1
}
## END FUNCTIONS

# Catch no args:
if [ "x$1" = "x" ]; then
	usage
fi

# Default Args
username=""
password=""
port=5984
OPTIND=1

while getopts ":h?H:d:f:u:p:P:" opt; do
	case "$opt" in
		h) usage;;
		H) url="$OPTARG" ;;
		d) db_name="$OPTARG" ;;
		f) file_name="$OPTARG" ;;
		u) username="$OPTARG";;
		p) password="$OPTARG";;
		P) port="${OPTARG}";;
		:) echo "... ERROR: Option \"-${OPTARG}\" requires an argument"; usage ;;
		*|\?) echo "... ERROR: Unknown Option \"-${OPTARG}\""; usage;;
	esac
done

# Trap unexpected extra args
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
if [ ! "x$@" = "x" ]; then
	echo "... ERROR: Unknown Option \"$@\""
	usage
fi

# Handle empty args
# url
if [ "x$url" = "x" ]; then
	echo "... ERROR: Missing argument '-H <COUCHDB_HOST>'"
	usage
fi
# db_name
if [ "x$db_name" = "x" ]; then
	echo "... ERROR: Missing argument '-d <DB_NAME>'"
	usage
fi
# file_name
if [ "x$file_name" = "x" ]; then
	echo "... ERROR: Missing argument '-f <OUTPUT_FILE>'"
	usage
fi

## Manage the passing of http/https for $url:
if [ ! "`echo $url | grep -c http`" = 1 ]; then
	url="http://$url"
fi

# Manage the addition of port
# If a port isn't already on our URL...
if [ ! "`echo $url | egrep -c ":[0-9]*$"`" = "1" ]; then
	# add it.
	url="$url:$port"
fi	

## Manage the addition of user+pass if needed:
# Ensure, if one is set, both are set.
if [ ! "x$username" = "x" ]; then
	if [ "x$password" = "x" ]; then
		echo "... ERROR: Password cannot be blank, if username is specified."
		usage
	fi
elif [ ! "x$password" = "x" ]; then
	if [ "x$username" = "x" ]; then
		echo "... ERROR: Username cannot be blank, if password is specified."
		usage
	fi
fi

# If neither username or password are empty, we need to add it to our URL.
if [ ! "x$username" = "x" ]&&[ ! "x$password" = "x" ]; then
	httptype="`echo $url | awk -F'/' '{print$1}'`"
	urlbase="`echo $url | awk -F'/' '{print$3}'`"
	url="${httptype}//${username}:${password}@${urlbase}"
fi

# Check if output already exists:
if [ -f ${file_name} ]; then
	echo "... ERROR: Output file ${file_name} already exists."
	exit 1
fi

# Grab our data from couchdb
curl -X GET "$url/$db_name/_all_docs?include_docs=true" -o ${file_name}
# Check for curl errors
if [ ! $? = 0 ]; then
	echo "... ERROR: Curl encountered an issue whilst dumping the database."
	rm -f ${file_name} 2>/dev/null
	exit 1
fi
# Check for export errors
ERR_CHECK="`head -n 1 ${file_name} | grep '^{"error'`"
if [ ! "x${ERR_CHECK}" = "x" ]; then
	echo "... ERROR: CouchDB reported: $ERR_CHECK"
	exit 1
fi

# CouchDB has a tendancy to output Windows carridge returns in it's output -
# This messes up us trying to sed things at the end of lines!
if [ "`file $file_name | grep -c CRLF`" = "1" ]; then
	echo "... INFO: File contains Windows carridge returns- converting..."
	tr -d '\r' < ${file_name} > ${file_name}.tmp
	if [ $? = 0 ]; then
		mv ${file_name}.tmp ${file_name}
		if [ $? = 0 ]; then
			echo "... INFO: Completed successfully."
		else
			echo "... ERROR: Failed to overwrite ${file_name} with ${file_name}.tmp"
			exit 1
		fi
	else
		echo ".. ERROR: Failed to convert file."
		exit 1
	fi
fi

## Now we parse the output file to make it suitable for re-import.
echo "... INFO: Amending file to make it suitable for Import."
echo "... INFO: Stage 1 - Document filtering"
sed -i 's/.*,"doc"://g' $file_name
if [ ! $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "... INFO: Stage 2 - Duplicate curly brace removal"
sed -i 's/}},$/},/g' $file_name
if [ ! $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "... INFO: Stage 3 - Header Correction"
sed -i '1s/^.*/{"docs":[/' $file_name
if [ ! $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "... INFO: Stage 4 - Final document line correction"
sed -i 's/}}$/}/g' $file_name
if [ ! $? = 0 ];then
	echo "Stage failed."
	exit 1
fi

echo "... INFO: Export completed successfully. File available at: ${file_name}"
