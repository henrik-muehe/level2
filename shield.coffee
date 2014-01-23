http = require('http')
httpProxy = require('./network_simulation/lib/proxy')
checkServer = require('./network_simulation/lib/check_server')
nopt = require('nopt')
url = require('url')

getMedian = (values)=>
  values.sort  (a,b)=> return a - b
  half = Math.floor values.length/2
  return values[half]

getMin = (values)=>
  values.sort  (a,b)=> return a - b
  return values[0]

class RequestData
  constructor: (@request, @response, @buffer)-> 

ipFromRequest = (reqData) -> reqData.request.headers['x-forwarded-for']

rejectRequest = (res) ->
  res.writeHead(400);
  res.end();


class Queue
  updateStats: (ip) =>
    record = @stats[ip] || { count: 0, lastConnects: [] }
    ++record.count;
    record.lastConnects.push(process.hrtime());
    @stats[ip] = record
    @counter = 0

  updateBlocked: =>
    counts = []
    connects = []
    for ip,s of @stats
      counts.push(s.count)
      if s.lastConnects.length >= 2
        a = s.lastConnects[s.lastConnects.length-2]
        b = s.lastConnects[s.lastConnects.length-1]
        diff = (b[0]*1e9 + b[1]) - (a[0]*1e9 + a[1])
        connects.push(diff)
    for ip,s of @stats    
      #@blocked[ip] = true if diff/1000000 < 150
      @blocked[ip] = s.count > 4 #getMin(counts)
      #if getMin(counts) == 1 
       # @blocked[ip] = true
      #console.log "#{ip} #{@blocked[ip]} #{s.count}"

    #console.log "Median counts " + getMedian(counts)
    #console.log "Median connect " + getMedian(connects)/1000000
    #console.log counts
    #console.log connects


  proxy: (elephant,req,res,buf) =>
    c = null
    min = 9999
    for p in @proxies
      p.pending ?= 0
      if p.pending < min
        c = p
        min = c.pending

    @queue ?= []

    if elephant 
      if c.pending == 0
        c.pending += 1
        return c.proxyRequest(req,res,buf)
      return rejectRequest(res)

    if c.pending < 6
      # send it straight out
      c.pending += 1
      console.log "straight #{elephant} #{c.pending}"

      c.proxyRequest(req,res,buf)
    else
      return rejectRequest(res)
      if not elephant
        @queue.push([req,res,buf])


  constructor: (@proxies, @parameters)->
    @info = ({ pending: 0, max: 6 } for p in @proxies)
    @stats = {}
    @blocked = {}

  takeRequest: (reqData) ->
    #  // Response delay in ms, Allowed in flight connections, Allowed queue length
    # var queue = new QueueServer(75, 2, 4);

    ip = ipFromRequest(reqData)
    @updateStats(ip)
    if (@counter < 25 || @counter % 10 == 0) 
      @updateBlocked()
    @counter += 1

    # Reject traffic as necessary:
    #if (!@idle() && @blocked[ipFromRequest(reqData)])
    #  rejectRequest(reqData);
    #  return;

    @proxy(@blocked[ip],reqData.request, reqData.response, reqData.buffer)

    #@proxies[Math.floor(Math.random()*@proxies.length)].proxyRequest();
  requestFinished: (proxy)=>
    if @queue.length > 0
      [a,b,c] = @queue.shift()
      console.log "dequeue mouse"
      return proxy.proxyRequest(a,b,c)
    proxy.pending -= 1
    




checkBackends = (targets, path, response) ->
  toCheck = targets.map (target) ->
    output = {};
    output['host'] = target['host'];
    output['port'] = target['port'];
    output['path'] = path;
    return output;
  success = ->
    response.writeHead(200, {"Content-Type": "application/json"});
    response.end()
  error = ->
    response.writeHead(500, {"Content-Type": "application/json"});
    response.end()
  checkServer.checkServers(toCheck, success, error)


main = ->
  opts = {
    "out-ports": String,
    "in-port": String,
  };
  parsed = nopt(opts)
  inPort = parsed['in-port'] || '3000';
  outPorts = if parsed['out-ports'] then parsed['out-ports'].split(",") else ['3001']
  targets = []
  target
  proxies = []
  proxy
  i

  for i in [0..(outPorts.length-1)]
    target = {'host': 'localhost', 'port': outPorts[i]}
    targets.push(target)
    proxy = new httpProxy.HttpProxy({'target': target})
    proxy.identifier = i
    proxies.push(proxy)

  queue = new Queue(proxies, {})
  for i in [0..(proxies.length-1)]
    proxy = proxies[i];
    proxy.index = i
    proxy.on("end", -> queue.requestFinished(this));

  server = http.createServer (req, res) =>
    if (req.method == "HEAD")
      checkBackends(targets, url.parse(req.url)['pathname'], res);
    else
      buffer = httpProxy.buffer(req)
      reqData = new RequestData(req, res, buffer)
      queue.takeRequest(reqData)

  server.on 'close', ->
    for i in [0..(proxies.length-1)]
      proxies[i].close();

  console.log("The shield is up and listening.");
  server.listen(inPort);

main();
