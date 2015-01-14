#!/bin/bash
##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
##

## this script outputs the content of a couchdb database on the stdoutput
## in a format that can be later uploaded with the bulk docs directive

## USAGE
## ** example: bash coucdb-dump mycouch.com my-db **
# syntax: bash couchdb-dump URL DB_NAME
## DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com
## DB_NAME: name of the database, e.g. 'my-db







###################### CODE STARTS HERE ###################

##START: HELPERS FUNCTIONS
function helpMsg {
	echo "** usage: bash couchdb-dump.sh DB_URL... DB_NAME..."
	echo "**  example: bash couchdb-dump.sh mycouch.com my-db"
    echo "**  DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com"
    echo "**  DB_NAME: name of the database, e.g. 'my-db'"
    echo "**  FILE_NAME: Filename for output (else it gets written to stdout)"
    echo ""

	}
## END HELPERS


##NO ARGS
if [ $# -lt 3 ]; then
	echo ":::::::::::::::::::::::::::::::::::::::::"
     echo 1>&2 "** $0: not enough arguments"
     helpMsg
     exit 2
elif [ $# -gt 3 ]; then
	echo ""
     echo 1>&2 "$0: too many arguments"
     helpMsg
fi


## VARS
url=$1
db_name=$2
#prop='doc'  NOT USED
file_name=$3

if [ ! "x${file_name}" = "x" ]&&[ -f ${file_name} ]; then
	echo "Output file ${file_name} already exists. Not overwritting. Exiting."
	exit 1
fi

curl -X GET http://$url:5984/$db_name/_all_docs?include_docs=true -o ${file_name}
if [ ! $? = 0 ]; then
	echo "An error was encountered whilst dumping the database."
	rm -f ${file_name} 2>/dev/null
	exit 1
fi

if [ "`file $file | grep -c CRLF`" = "1" ]; then
	echo "File contains Windows carridge returns- converting..."
	tr -d '\r' < $file > ${file}.tmp
	if [ $? = 0 ]; then
		mv ${file}.tmp ${file}
		if [ $? = 0 ]; then
			echo "Completed successfully."
		else
			echo "An error occured whilst overwriting the original file."
			exit 1
		fi
	else
		echo "An error occured when trying to convert."
		exit 1
	fi
fi
echo "Amending file to make it suitable for Import."
echo "Stage 1 - Document filtering"
sed -i 's/.*,"doc"://g' $file_name
if [ $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "Stage 2 - Duplicate curly brace removal"
sed -i 's/}},$/},/g' $file_name
if [ $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "Stage 3 - Header Correction"
sed -i '1s/^.*/{"docs":[/' $file_name
if [ $? = 0 ];then
	echo "Stage failed."
	exit 1
fi
echo "Stage 4 - Final document line correction"
sed -i 's/}}$/}/g' $file_name
if [ $? = 0 ];then
	echo "Stage failed."
	exit 1
fi

echo "Export completed successfully. File available at: ${file_name}"
