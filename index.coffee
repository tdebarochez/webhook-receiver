#!/usr/bin/env coffee
fs = require 'fs'
path = require 'path'
child_process = require('child_process')
spawn = child_process.spawn
exec = child_process.exec
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
    console.log "ok"
  catch e
    process.exit 3
  return

if '--help' in process.argv or '-h' in process.argv or '--usage' in process.argv
  console.log """
  webhook-receiver: HTTP server, used to execute simple tasks in background
  Usage:
    --background     run HTTP server in background
    --help           display this message
    --kill           kill background running server
    --restart        restart background HTTP server
    --truncate-logs  empty log files
  """
  return

http = require 'http'
querystring = require 'querystring'
url = require('url')

short_msg = (res, code, msg) ->
  res.writeHead code, 'Content-Type': 'text/plain'
  return res.end msg
log = (req, msg) ->
  console.log "[" + (new Date) + "] " + req.socket.remoteAddress + " " + req.method + ' "' + req.url + '" : ' + msg
error = (req, err) ->
  if typeof err is "string"
    log req, "ERROR #{err}"
  else
    log req, "error #{err}"

http.createServer( (req, res) ->
  statTarget = (req, res, filename) ->
    return (err, stat) ->
      if err
        return short_msg res, 404, "target not found"
      if not stat.isFile()
        log req, "[#{filename}] is not a file"
        return short_msg res, 404, "target not found"
      if not ((stat.uid is process.getuid() and stat.mode & 0o0100) or
              (stat.gid is process.getgid() and stat.mode & 0o0010) or
              (stat.mode & 0o0001))
        error req, "[#{filename}] is not executable"
        return short_msg res, 500, "nok"
      tmp = querystring.parse if req.method is 'GET' then url.parse(req.url).query else datas.toString()
      params = []
      for key, value of tmp
        params.push "#{key}=#{value}"
      try
        target = spawn filename, params,
          detached: true,
          stdio: [ 'ignore', out, err ]
        fs.writeFileSync filename + '.pid', target.pid
        target.unref()
      catch e
        console.log(filename)
        error req, e
        return short_msg res, 500, "nok"
      log req, "execute [#{filename}]"
      return short_msg res, 200, "ok"

  onCompleteReceive = (req, res) ->
    return ->
      if req.method is not "GET" and req.method is not "POST"
        return short_msg res, 405, "bad HTTP verb"
      filename = url.parse(req.url).pathname.replace /[^\d\w]+/g, ""
      if filename is ""
        return short_msg res, 400, "target missing"
      filename = path.join(__dirname, "targets", req.method, filename)
      fs.stat filename, statTarget(req, res, filename)

  datas = new Buffer 0
  req.on "data", (chunk) ->
    datas = new Buffer datas.toString() + chunk.toString()
  req.on "end", onCompleteReceive(req, res)
).listen conf.tcp_port, conf.tcp_address
console.log 'Server running at http://' + conf.tcp_address + ':' + conf.tcp_port + '/'
