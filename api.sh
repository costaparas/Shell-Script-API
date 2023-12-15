#!/bin/sh

export PATH="/bin:/usr/bin/:/usr/local/bin:$PATH"
unset CDPATH IFS TMPDIR
umask 0077

read -r request_line
request_method=$(printf "%s" "$request_line" | sed 's/ .*//')
if printf "%s" "$request_method" | grep -qi '^post'
then
    body=1
    request_body=$(mktemp)
    trap 'rm -f $request_body' EXIT INT TERM
elif printf "%s" "$request_method" | grep -qi '^get'
then
    body=0
    query_string=$(printf "%s" "$request_line" | sed 's/^[^?]*?//')
else
    cat <<eof
HTTP/1.1 405 Method Not Allowed
Content-type: application/json

{"method": "$request_method", "msg": "Not allowed"}
eof
    exit 0
fi

content_length=0
in_body=0

while IFS='' read -r line
do
    if test $in_body -eq 1
    then
        # Collect payload
        printf "%s\n" "$line" >> $request_body
        received_length=$(wc -c < $request_body)
        if test $received_length -ge $content_length
        then
            break
        fi
    elif printf "%s" "$line" | grep -qv ':'
    then
        if test $content_length -eq 0
        then
            break  # There is no body
        else
            in_body=1  # Body starts on the next line
        fi
    elif printf "%s" "$line" | grep -qi '^content-length:'
    then
        content_length=$(printf "%s" "$line" | sed 's/.*:\s*//')
    else
        :  # Placeholder - collect other headers as needed
    fi
done

if test $body -eq 1
then
    num_keys=$(jq length < $request_body)
    test -z "$num_keys" && num_keys=0
    content="{\"method\": \"$request_method\", \"num_keys\": $num_keys}"
else
    num_params=$(printf "%s" "$query_string" | grep -o '=' | wc -l)
    content="{\"method\": \"$request_method\", \"num_params\": $num_params}"
fi

cat <<eof
HTTP/1.1 200 OK
Content-type: application/json

$content
eof
