# Turning a Shell Script Into a Web API

To a developer, [shell scripts](https://en.wikipedia.org/wiki/Shell_script) are an indispensable tool used regularly for routine tasks. But we are not here to discuss routine tasks. We are here to discuss a relatively unconventional use case of shell scripting.

We will explore several ways to build a fully functional [REST](https://en.wikipedia.org/wiki/REST)-like [web API](https://en.wikipedia.org/wiki/Web_API) written in shell.

But, before we begin...

I would like to point out even though it is possible to build a shell script API, there aren't too many practical reasons for doing so. Among the limitations of shell script APIs, the biggest two in my view are security and scalability. As such, for many readers, this outline may only be useful for academic purposes.

It is not my intention to engage in a philosophical debate over whether it is a good idea to even consider building a shell script API, or discuss the reasons for or against carrying out such a task. I simply aim to explore possible methods that are practically available.

Now we can start...

## Prerequisites

- Experience with writing Unix shell scripts. All code snippets use [POSIX](https://en.wikipedia.org/wiki/POSIX)-compliant shell.
- Familiarity with building and running [Docker](https://en.wikipedia.org/wiki/Docker_(software)) containers. The APIs can be run standalone, but using Docker makes it more convenient and practical.
- Knowledge of the [Common Gateway Interface (CGI)](https://en.wikipedia.org/wiki/Common_Gateway_Interface). This is used by some, but not all, of the methods.
- Familiarity with [HTTP](https://en.wikipedia.org/wiki/HTTP). The APIs will be built on top of HTTP.

![](img/docker.jpg)

## API structure

We will construct a simple REST API that processes [GET](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/GET) and [POST](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/POST) requests only, each representing quite a distinct flow. For simplicity, all other methods will yield a [405 Method Not Allowed](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/405) response. It is easy to generalize the GET and POST handling to support the other common [HTTP methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods), such as [DELETE](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/DELETE) and [PUT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/PUT).

Our API will use [JSON](https://www.json.org) for the request and response format.

It will have a single endpoint, being the root. For simplicity, we will not process the [path component](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL#path_to_resource) of the [request URL](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL)---so that requests with different paths are treated uniformly. For example, GET requests for `http://localhost:8080`, `http://localhost:8080/dummy` and `http://localhost:8080/dummy/0` ought to yield the same response from our API.

The API will accept an arbitrary list of [query string](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL#parameters) parameters in the case of GET, and an arbitrary set of key-value pairs in the POST [request body](https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages#body).

Its response format will look like this in the case of GET requests:

```json
{"method": "GET", "num_params": INTEGER}
```

where `INTEGER` is the number of query string parameters.

For POST requests, the response format will take this form:

```json
{"method": "POST", "num_keys": INTEGER}
```

where `INTEGER` is the number of top-level keys in the request body.

Additionally, our API will not perform any validation of the query string, nor of the request body. In practise, the query string (in the case of GET) and the body (in the case of POST) ought to be fully validated, with a [400 Bad Request](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/400) error returned if it is found to be invalid.

As such, our API will simply return a [200 OK](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/200) response for all supported methods.

## Command line utility software

There exist a range of command-line networking tools that can be used to communicate over [TCP](https://en.wikipedia.org/wiki/Transmission_Control_Protocol), the protocol on which HTTP depends.

We can use such tools to listen on a [port](https://en.wikipedia.org/wiki/Port_(computer_networking)) of our choosing, and have the software forward incoming requests onto an executable of our choice.

In other words, we can write a shell script to handle incoming requests and specify that shell script as the request handler to the command line tool.

Here, we will consider 3 such tools.

### Writing the shell script

We will put together a shell script that follows the API structure described earlier. It will process the incoming request method, [headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages#headers), body and query string as needed and then respond with an appropriate [status code](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status) and [response body](https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages#body_2).

There are 3 steps to the script, so let's take a look at each one in turn.

You can download the complete version of the shell script from [here](https://github.com/costaparas/Shell-Script-API/blob/main/api.sh).

### Process request method and obtain parameters

```sh
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
```

The entire request can be read from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)). The first step is to just process the first line of the request, which gives us (among other things), the request method and the query string parameters.

#### Handling POST requests

In the case of POST, we simply prepare a [temporary file](https://en.wikipedia.org/wiki/Temporary_file) using [`mktemp`](https://www.gnu.org/software/autogen/mktemp.html) that can be used to store the request body. That will be done in the next step.

#### Handling GET requests

In the case of GET, we can directly extract the query string from the first line of input using [`sed`](https://www.gnu.org/software/sed/manual/sed.html).

#### Handling other requests

For all other request methods, we will just return a response immediately. This has a 405 status code and a corresponding descriptive JSON body.

### Process request body

```sh
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
```

This step only applies to POST requests in our case, but more generally applies to any method for which a body is typically expected---[PUT](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/PUT) and [PATCH](https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/PATCH).

Due to the lack of [EOF](https://en.wikipedia.org/wiki/End-of-file) in the standard input, we must collect the request body line by line using [`read`](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html#index-read).

In our case, the only header we need to process is the [Content-length](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Length), which enables us to capture all bytes of the request body and terminate at the right time.

Our code simply reads the body one line at a time and writes it to the temporary file for subsequent processing. It doesn't perform any additional validation.

### Prepare and return response

```sh
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
```

In the final step, we determine the number of keys or number of query parameters and return (i.e. print) the response.

For POST requests, we use [`jq`](https://jqlang.github.io/jq/) to process the JSON body. Invalid JSON will simply result in zero keys.

For GET requests, we will assume a [URL-encoded](https://en.wikipedia.org/wiki/Percent-encoding) query string, taking the number of `=` symbols to be the number of query parameters.

### Running with `netcat`

![](img/netcat.jpg)

Though often used as a networking analysis and debugging tool, it is possible to adapt [`netcat`](https://en.wikipedia.org/wiki/Netcat) to fit our use case.

Please note this is possible when using a version of `netcat` called `netcat-traditional`. It is not supported with `netcat-openbsd`.

So, using your favorite package manager, first install `netcat-traditional` on your system. Some Linux distributions ship with a version of `netcat` already installed. In any case, you will need `netcat-traditional` for the following to work.

With the shell script request handler placed in a file called `api.sh`, you should be able to run the following:

```sh
chmod 0700 api.sh
nc -l localhost -p 8080 -e ./api.sh
```

This will open [localhost](https://en.wikipedia.org/wiki/Localhost) port 8080 and forward all requests to the shell script.

We can use [`curl`](https://curl.se/) to make a request to the API as follows:

```sh
curl "http://localhost:8080?param1=value1&param2=value2"
```

The response ought to be:

```json
{"method": "GET", "num_params": 2}
```

You will notice that `netcat` quits immediately after this single request. To keep `netcat` running so that it can process successive requests, we need to run it in an infinite loop like this:

```sh
while true
do
    nc -l localhost -p 8080 -e ./api.sh
done
```

All this does is re-run `netcat` after each request is finished. The main drawback is that it can only handle sequential requests, not concurrent requests.

There is no remedy for this, and as such, this makes `netcat` quite limited. The subsequent methods we'll look at do not have this limitation.

### Running with `socat`

The [`socat`](https://linux.die.net/man/1/socat) utility is a much more powerful tool than `netcat`. In particular, it overcomes the limitation of not being able to handle concurrent connections. It does this by forking a new process for each request.

The following [Dockerfile](https://docs.docker.com/engine/reference/builder/) will get the server up and running:

```docker
FROM ubuntu:latest

RUN apt-get update && \
    apt-get install -y socat jq && \
    rm -rf /var/lib/apt/lists/* && \
    useradd local

WORKDIR /app
USER local

COPY --chown=local:local api.sh .
RUN chmod 0500 api.sh

CMD [ "socat", "tcp-listen:8080,reuseaddr,fork", "system:'./api.sh'" ]
```

I've used a [Ubuntu](https://ubuntu.com/) [base image](https://docs.docker.com/build/building/base-images/) and installed both `socat` and `jq`. In addition, `socat` is run as a non-root user which I've called `local`. Note that the handler script itself only needs read and execute permission in the Docker image, so I've purposely not enabled write permission.

You can download the Dockerfile from [here](https://github.com/costaparas/Shell-Script-API/blob/main/Dockerfile_socat) and build and run it like this:

```sh
docker build -f Dockerfile_socat -t socat-api .
docker run -p 8080:8080 socat-api
```

You should be able to successfully run the `curl` request from before with the same result.

```sh
curl "http://localhost:8080?param1=value1&param2=value2"
```

You can also try a POST request to make sure the script is working as expected:

```sh
curl "http://localhost:8080" --data-binary @- << EOF
{
    "field1": "test",
    "field2": {
        "foo": "bar",
        "hello": "world"
    },
    "field3": "test2"
}
EOF
```

That should give the following result:

```json
{"method": "POST", "num_keys": 3}
```

### Running with `tcpserver`

The final version I'd like to mention is [`tcpserver`](https://cr.yp.to/ucspi-tcp/tcpserver.html). This is a program perfectly suited for the typical HTTP request-response flow.

To use it locally, you need to install the `ucspi-tcp` package. After that, it is quite simple to use:

```sh
tcpserver 127.0.0.1 8081 ./api.sh
```

I suggest downloading the Dockerfile from [here](https://github.com/costaparas/Shell-Script-API/blob/main/Dockerfile_tcpserver) and using it like so:

```sh
docker build -f Dockerfile_tcpserver -t tcp-api .
docker run -p 8081:8081 tcp-api
```

The Dockerfile is identical to the one used for `socat`, except for the package installed and the `CMD` to run.

This time, let's test out the API with an empty request body:

```sh
curl "http://localhost:8081" -d ""
```

You should get this response:

```json
{"method": "POST", "num_keys": 0}
```

## CGI-enabled web server software

Now let's explore a completely different approach to creating and running a shell script API---by using CGI.

The [CGI specification](https://www.rfc-editor.org/rfc/rfc3875) prescribes that specific [environment variables](https://en.wikipedia.org/wiki/Environment_variable) are supplied to the CGI script by the web server software, such as [`CONTENT_TYPE`](https://www.rfc-editor.org/rfc/rfc3875#section-4.1.3), [`CONTENT_LENGTH`](https://www.rfc-editor.org/rfc/rfc3875#section-4.1.2), [`REQUEST_METHOD`](https://www.rfc-editor.org/rfc/rfc3875#section-4.1.12) and [`QUERY_STRING`](https://www.rfc-editor.org/rfc/rfc3875#section-4.1.7). In addition, well-behaved web server software typically supply an end-of-file character after `CONTENT_LENGTH` bytes have been read, although technically the [RFC](https://en.wikipedia.org/wiki/Request_for_Comments) does not mandate this.

The above makes writing a shell script API much simpler than with the previous approach, as you'll soon see.

As for choosing the web server software itself, there are several viable options. [Here](https://en.wikipedia.org/wiki/Comparison_of_web_server_software#Features) is a list indicating those which support CGI. We'll consider two popular ones, but the CGI script would be identical if you choose to use something different.

### Writing the CGI script

As before, our script must determine the request method first, and then obtain the input as appropriate.

This time, we do not have to manually parse the request line to obtain the request method and query string, as they are available as environment variables we can simply read directly.

In addition, we can use [`cat`](https://linux.die.net/man/1/cat) to read the entire request body from standard input, since an EOF character ought to be present. This completely eliminates the manual processing needed previously.

```sh
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
```

The rest of the script is pretty similar to the previous version. The main difference in the logic is that the request body is in a variable this time instead of a temporary file, so the way we invoke `jq` differs.

```sh
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
```

The other thing to be mindful of is that the CGI script does not write the status line of the response, as the CGI server handles that. Therefore, the first line of the [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) of our script is not the status line, but simply a `Status` CGI header field. Although this is optional in the case of a 200 response, it is included here for completeness.

You can download the complete version of the shell script from [here](https://github.com/costaparas/Shell-Script-API/blob/main/api.cgi).

### Running with `apache2`

![](img/apache.jpg)

We can use the official [`apache2`](https://httpd.apache.org/) Docker image to set up our CGI server as follows:

```docker
FROM httpd:latest

RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*

ENV CGI_BIN /usr/local/apache2/cgi-bin
WORKDIR $CGI_BIN
COPY api.cgi .
RUN chmod 0555 api.cgi
ENTRYPOINT httpd-foreground -c "LoadModule cgid_module modules/mod_cgid.so"
```

Our CGI script is copied to the default `cgi-bin/` subdirectory of the web server. To start up the server, note two things:

- We invoke the server in the foreground, so that it continues in perpetuity.
- We have to enable the CGI module upon server startup, since it is disabled by default for security.

You can download the Dockerfile from [here](https://github.com/costaparas/Shell-Script-API/blob/main/Dockerfile_apache2) and build and run it like this:

```sh
docker build -f Dockerfile_apache2 -t apache-api .
docker run -p 8082:80 apache-api
```

Note that `apache2` exposes port 80 by default.

Requests to the API will look a little different due to the location and name of the script. For example:

```sh
curl "http://localhost:8082/cgi-bin/api.cgi?foo=bar&a=b&hello=world&qwerty=uiop"
```

Expected response:

```json
{"method": "GET", "num_params": 4}
```

Similarly, you can try out the POST requests from earlier as well.

### Running with `lighttpd`

![](img/lighttpd.jpg)

As an alternative to Apache, we can use [`lighttpd`](https://www.lighttpd.net/) to deploy our CGI script-based API.

There is no official Docker image maintained for `lighttpd`, so we will build it ourselves on top of a Ubuntu base image.

You can download the necessary Dockerfile fom [here](https://github.com/costaparas/Shell-Script-API/blob/main/Dockerfile_lighttpd) and build and run it like so:

```sh
docker build -f Dockerfile_lighttpd -t light-api .
docker run -p 8083:80 light-api
```

As with Apache, port 80 is the default port exposed.

Our Dockerfile is quite similar to that used for Apache, in that the CGI script is placed in the `cgi-bin/` subdirectory, and we must start the server in the foreground as well. The main difference is that we have to manually install `lighttpd` ourselves.

A request similar to the previous one should work perfectly fine and yield the same result:

```sh
curl "http://localhost:8083/cgi-bin/api.cgi?foo=bar&a=b&hello=world&qwerty=uiop"
```

We can also test out the API by making a PUT request. Let's also enable the `-v` option, so we can verify the status code.

```sh
curl "http://localhost:8083/cgi-bin/api.cgi" -X PUT -v
```

In this case, we'd expect a response like so:

```json
{"method": "PUT", "msg": "Not allowed"}
```

You should also see the status line in the response headers as part of `curl`'s output.

---

The original sources are available on [GitHub](https://github.com/costaparas/Shell-Script-API).

*Please consider the environment before printing.*
