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
    echo ""

	}
## END HELPERS


##NO ARGS
if [ $# -lt 2 ]; then
	echo ":::::::::::::::::::::::::::::::::::::::::"
     echo 1>&2 "** $0: not enough arguments"
     helpMsg
     exit 2
elif [ $# -gt 2 ]; then
	echo ""
     echo 1>&2 "$0: too many arguments"
     helpMsg
fi


## VARS
url=$1
db_name=$2
#prop='doc'  NOT USED



##vars for the loop
i=0
while read json
do
    if [ $i -eq 0 ]; then
        echo "{\"docs\":["
        echo "" >>provino.txt
        echo "" >>out.txt
    else    
        rm provino.txt out.txt
        echo $json | sed 's/$//'>> provino.txt

        # last 'sed' in next line needs explanations: it is added for the last line (with no trailing comma, but just brackets)
        cat provino.txt | sed  's/{\"id\":.*,\"key\".*,\"value\":.*,\"doc\"://' | sed 's/},$/,/' | sed 's/}$//' >>out.txt
        cat out.txt
    fi
    let "i += 1" 
done < <(echo "`curl -X GET http://$url:5984/$db_name/_all_docs?include_docs=true`")
echo "}"
rm provino.txt out.txt
