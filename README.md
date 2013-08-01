Webhook-receiver
===

I did not found easy way to manage simple tasks behind POST webhooks: that's why I create this little script. It "translate" HTTP parameters to command line parameters and execute your scripts in background (as a daemon do).

Requirements
---

  + nodejs
  + coffescript

Installation
---

    $ git clone <this repo>
    $ ./index.coffee --background

At this point, the HTTP server is listening on `127.0.0.1`, port `1337`. You can change this by renamming the `config.json.example` file to `config.json`, edit it and restart the server by typing `$ ./index.coffee --restart`. Once your HTTP server is ready, you can add your own executables scripts to `targets/GET/` or `targets/POST/`. HTTP parameters will be translate to $1, $2, $3, etc...

For example, if the HTTP request is the next :

    GET /test?--username=john&--password=smith

Your script called will be execute like this :

    ./targets/GET/test "--username=john" "--password=smith"

Todo
---

In priority order

  + filter by IPs (or IP range)
  + HTTPS
  + HTTP authentication
  + define a user to execute tasks

The three first can be done with a good reverse proxy (like nginx do well) and the last one can be done in the script itself.

License
---

MIT