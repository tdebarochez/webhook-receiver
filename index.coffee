#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'
child_process = require('child_process')
spawn = child_process.spawn
exec = child_process.exec
out_childs = fs.openSync path.join(__dirname, 'logs', 'stdout.childs'), 'a'
err_childs = fs.openSync path.join(__dirname, 'logs', 'stderr.childs'), 'a'
access_log = fs.createWriteStream path.join(__dirname, 'logs', 'access'), {flags: 'a'}
error_log = fs.createWriteStream path.join(__dirname, 'logs', 'error'), {flags: 'a'}
out = fs.openSync path.join(__dirname, 'logs', 'stdout'), 'a'
err = fs.openSync path.join(__dirname, 'logs', 'stderr'), 'a'
conf = if fs.existsSync path.join(__dirname, "config.json") then require path.join(__dirname, "config.json") else {}

conf.tcp_port ||= 1337
conf.tcp_address ||= '127.0.0.1'

runInBackground = () ->
  child = spawn 'coffee', [__filename],
    detached: true,
    stdio: [ 'ignore', out, err ]
  fs.writeFileSync 'pid', child.pid
  child.unref()

killBackgroundProcess = () ->
  if not fs.existsSync 'pid'
    console.error "pid file missing, is server running ?"
    return false
  pid = fs.readFileSync 'pid'
  process.kill pid
  fs.unlink 'pid'
  fs.writeSync out, 'kill ' + pid + '\n'
  return true

if '--background' in process.argv
  runInBackground()
  return

if '--kill' in process.argv
  if not killBackgroundProcess()
    process.exit 2
  return

if '--restart' in process.argv
  killBackgroundProcess()
  setTimeout runInBackground(), 200
  return

if '--truncate-logs' in process.argv
  try
    fs.ftruncateSync out, 0
    fs.ftruncateSync err, 0
    fs.ftruncateSync out_childs, 0
    fs.ftruncateSync err_childs, 0
    fs.ftruncateSync access_log, 0
    fs.ftruncateSync error_log, 0
    console.log "ok"
  catch e
    process.exit 3
  return

if '--targets' in process.argv
  for method in ["POST", "GET"]
    console.log "[#{method}]"
    targets = fs.readdirSync(path.join(__dirname, "targets", method)).filter (filename) ->
      not filename.match /(\.pid|^.gitignore)$/g
    if targets.length < 1
      console.log "  (none)"
    else
      for target in targets
        console.log "  #{target}"
  return

if '--help' in process.argv or '-h' in process.argv or '--usage' in process.argv
  console.log """
  webhook-receiver: HTTP server, used to execute simple tasks in background
  Usage:
    --background         run HTTP server in background
    -h, --help, --usage  display this message
    --kill               kill background running server
    --restart            restart background HTTP server
    --targets            list all targets
    --truncate-logs      empty log files
  """
  return

http = require 'http'
querystring = require 'querystring'
url = require('url')

short_msg = (req, res, code, msg, header_alredy_sent) ->
  remote_ip = if "x-forwarded-for" of req.headers then req.headers['x-forwarded-for'] else req.socket.remoteAddress
  log_message = "[" + (new Date) + "] " + remote_ip + " " + req.method + ' "' + req.url + '" (' + code + ')' + (if code >= 200 then " : #{msg}" else "")
  access_log.write log_message + "\n"
  if not header_alredy_sent
    res.writeHead code, 'Content-Type': 'text/plain'
  return res.end msg
log = (req, msg) ->
  console.log "[" + (new Date) + "] " + msg
error = (req, err) ->
  error_log.write "[" + (new Date) + "] #{err}\n"

http.createServer( (req, res) ->
  statTarget = (req, res, filename, specific_conf) ->
    return (err, stat) ->
      if err
        error req, err
        return short_msg req, res, 404, "target not found"
      if req.method is "HEAD"
        return short_msg req, res, 200, ""
      if not stat.isFile()
        log req, "[#{filename}] is not a file"
        return short_msg req, res, 404, "target not found"
      if not ((stat.uid is process.getuid() and stat.mode & 0o0100) or
              (stat.gid is process.getgid() and stat.mode & 0o0010) or
              (stat.mode & 0o0001))
        error req, "[#{filename}] is not executable"
        return short_msg req, res, 500, "nok"
      if req.method is 'GET'
        tmp = querystring.parse url.parse(req.url).query
      else
        tmp = datas.toString()
        if "content-type" of req.headers and req.headers['content-type'] is "application/json"
          tmp = JSON.parse tmp
        else
          tmp = querystring.parse tmp
      params = []
      for key, value of tmp
        params.push "#{key}=#{value}"
      detach = if specific_conf.detach in [true, false] then specific_conf.detach else true
      log req, "execute [#{filename}] " + if detach then "d" else ""
      try
        if detach
          target = spawn filename, params,
            detached: true,
            stdio: [ 'ignore', out_childs, err_childs ]
          target.unref()
        else
          res.writeHead 200, 'Content-Type': 'text/plain'
          target = spawn filename, params
          target.stdout.on 'data', (buffer)->
            res.write buffer
          target.stderr.on 'data', (buffer)->
            res.write buffer
          target.on 'close', (code)->
            log req, "return [#{filename}] " + code
            short_msg req, res, 200, "ok", true
        fs.writeFileSync filename + '.pid', target.pid
      catch e
        console.log(filename)
        error req, e
        return short_msg req, res, 500, "nok"
      if detach
        return short_msg req, res, 200, "ok"

  onCompleteReceive = (req, res) ->
    return ->
      if req.method not in ["GET", "POST", "HEAD"]
        return short_msg req, res, 405, "bad HTTP verb"
      filename = url.parse(req.url).pathname.replace(/\.+/g, '.').replace /[^\d\w\-\.]+/g, ""
      if filename is ""
        return short_msg req, res, 400, "target missing"
      specific_conf = {}
      if conf.repo_specific and conf.repo_specific[filename]
        specific_conf = conf.repo_specific[filename]
      filename = path.join(__dirname, "targets", req.method, filename)
      fs.stat filename, statTarget(req, res, filename, specific_conf)

  datas = new Buffer 0
  req.on "data", (chunk) ->
    datas = new Buffer datas.toString() + chunk.toString()
  req.on "end", onCompleteReceive(req, res)
).listen conf.tcp_port, conf.tcp_address
console.log 'Server running at http://' + conf.tcp_address + ':' + conf.tcp_port + '/'
