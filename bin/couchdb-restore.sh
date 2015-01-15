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

## This script is to restore a couchdb database-file to a couchdb database instance.
## FILE should be:
##  1. result of a couchdb-dump.sh command
##  2. OR formatted as explained @ http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API

## USAGE
## ** example: ./couchdb-restore.sh -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password

###################### CODE STARTS HERE ###################

##START: FUNCTIONS
usage() {
	echo
	echo "Usage: $0 -H <COUCHDB_HOST> -d <DB_NAME> -f <INPUT_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines_per_batch>]"
        echo -e "\t-h   Display usage information."
        echo -e "\t-H   CouchDB URL. Can be provided with or without 'http://'"
        echo -e "\t-d   CouchDB Database name to import to."
        echo -e "\t-f   File containing json to import."
	echo -e "\t-l   Number of lines to process at a time. [Default: 5000]"
        echo -e "\t-P   Provide a port number for CouchDB [Default: 5984]"
        echo -e "\t-u   Provide a username for auth against CouchDB [Default: blank]"
        echo -e "\t-p   Provide a password for auth against CouchDB [Default: blank]"
        echo
	echo "Example: $0 -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password"
	echo
        exit 1
}
## END FUNCTIONS

# Catch no args:
if [ "x$1" = "x" ]; then
        usage
fi

# Default args
username=""
password=""
port=5984
lines=5000
OPTIND=1

while getopts ":h?H:d:f:l:u:p:P:" opt; do
        case "$opt" in
                h) usage;;
                H) url="$OPTARG" ;;
                d) db_name="$OPTARG" ;;
                f) file_name="$OPTARG" ;;
		l) lines="$OPTARG" ;;
                u) username="$OPTARG";;
                p) password="$OPTARG";;
                P) port="${OPTARG}";;
                :) echo "... ERROR: Option \"-${OPTARG}\" requires an argument"; usage ;;
                *|\?) echo "... ERROR: Unknown Option \"-${OPTARG}\""; usage;;
        esac
done

### VALIDATION START

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

# Check if input exists:
if [ ! -f ${file_name} ]; then
        echo "... ERROR: Input file ${file_name} not found."
        exit 1
fi

#### VALIDATION END

# If the size of the file to import is less than our $lines size, don't worry about splitting
if [ `wc -l $file_name | awk '{print$1}'` -lt $lines ]; then
	echo "... INFO: Small dataset. Importing as a single file."
	curl -d @$file_name -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json'
# Otherwise, it's a large import that requires bulk insertion.
else
	echo "... INFO: Block import set to ${lines} lines."
	if [ -f ${file_name}.split000000 ]; then
		echo "... ERROR: Split files \"${file_name}.split*\" already present. Please remove before continuing."
		exit 1
	fi
	echo "... INFO: Generating files to import"
	### Split the file into many
	split --numeric-suffixes --suffix-length=6 -l ${lines} ${file_name} ${file_name}.split
	if [ ! "$?" = "0" ]; then
		echo "... ERROR: Unable to create split files."
		exit 1
	fi
	HEADER="`head -n 1 $file_name`"
	FOOTER="`tail -n 1 $file_name`"
	
	A=0
	NUM=0
	until [ $A = 1 ];do
		PADNUM=`printf "%06d" $NUM`
		PADNAME="${file_name}.split${PADNUM}"
		if [ -f ${PADNAME} ]; then
			if [ ! "`head -n 1 ${PADNAME}`" = "${HEADER}" ]; then
				echo "... INFO: Adding header to ${PADNAME}"
				sed -i "1i${HEADER}" ${PADNAME}
			else
				echo "... INFO: Header already applied to ${PADNAME}"
			fi
			if [ ! "`tail -n 1 ${PADNAME}`" = "${FOOTER}" ]; then
				echo "... INFO: Adding footer to ${PADNAME}"
				sed -i '$s/,$//g' ${PADNAME}
				echo "${FOOTER}" >> ${PADNAME}
			else
				echo "... INFO: Footer already applied to ${PADNAME}"
			fi
			echo "... INFO: Inserting ${PADNAME}"
			curl -d @${PADNAME} -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json' -o tmp.out
			if [ ! $? = 0 ]; then
				echo "... ERROR: Curl failed trying to restore ${PADNAME} - Stopping"
				exit 1
			elif [ "`head -n 1 tmp.out | grep -c '^{"error'`" = 1 ]; then
				echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
				exit 1
			else
				rm -f ${PADNAME}
				rm -f tmp.out
			fi
			(( NUM++ ))
		else
			echo "... INFO: Successfully Imported `expr ${NUM} - 1` Files"
			A=1
		fi
	done
fi
