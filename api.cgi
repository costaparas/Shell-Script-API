#!/bin/sh

export PATH="/bin:/usr/bin/:/usr/local/bin:$PATH"
unset CDPATH IFS TMPDIR
umask 0077

if printf "%s" "$REQUEST_METHOD" | grep -qi '^post'
then
    body=1
    request_body=$(cat)
elif printf "%s" "$REQUEST_METHOD" | grep -qi '^get'
then
    body=0
    query_string=$QUERY_STRING
else
    cat <<eof
Status: 405
Content-type: application/json

{"method": "$REQUEST_METHOD", "msg": "Not allowed"}
eof
    exit 0
fi

if test $body -eq 1
then
    num_keys=$(printf "%s" "$request_body" | jq length)
    test -z "$num_keys" && num_keys=0
    content="{\"method\": \"$REQUEST_METHOD\", \"num_keys\": $num_keys}"
else
    num_params=$(printf "%s" "$query_string" | grep -o '=' | wc -l)
    content="{\"method\": \"$REQUEST_METHOD\", \"num_params\": $num_params}"
fi

cat <<eof
Status: 200
Content-type: application/json

$content
eof
