#!/bin/bash



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
	echo "** usage: bash couchdb-dump DB_URL... DB_NAME..."
	echo "**  example: bash coucdb-dump mycouch.com my-db"
    echo "**  DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com"
    echo "**  DB_NAME: name of the database, e.g. 'my-db'"
    echo ""

	}
##thanks to Carlos Justiniano for this function (https://gist.github.com/cjus)
function jsonval {
    temp=`echo $json | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $prop`
    echo ${temp##*|}
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
prop='doc' 



##vars for the loop
i=0
outJSON=""
while read json
do
    if [ $i -eq 0 ]; then
        echo "{\"docs\":["
    else
        picurl=`jsonval`
        echo "$json"
    fi
    let "i += 1" 
done < <(echo "`curl -X GET http://$url:5984/$db_name/_all_docs?include_docs=true`")
