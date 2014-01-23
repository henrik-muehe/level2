http = require('http')
httpProxy = require('./network_simulation/lib/proxy')
checkServer = require('./network_simulation/lib/check_server')
nopt = require('nopt')
url = require('url')

getMedian = (values)=>
  values.sort  (a,b)=> return a - b
  half = Math.floor values.length/3
  return values[half]

class RequestData
  constructor: (@request, @response, @buffer)-> 

ipFromRequest = (reqData) -> reqData.request.headers['x-forwarded-for']

rejectRequest = (reqData) ->
  reqData.response.writeHead(400);
  reqData.response.end();

stats = {}
blocked = {}

class Queue
  constructor: (@proxies, @parameters)->
  takeRequest: (reqData) ->
    if (!stats[ipFromRequest(reqData)])
      stats[ipFromRequest(reqData)] = 0;
    stats[ipFromRequest(reqData)] += 1;

    if Math.floor(Math.random()*5) == 1
      blocked = {}
      #console.log stats
      count = 0
      vals = []
      for k,v of stats 
        count += 1
        vals.push v

      if count > 3
        m = getMedian vals
        #console.log m
        for k,v of stats
          blocked[k] = true if v >= 2*m


    # Reject traffic as necessary:
    if (blocked[ipFromRequest(reqData)])
      rejectRequest(reqData);
      return;

    @proxies[Math.floor(Math.random()*@proxies.length)].proxyRequest(reqData.request, reqData.response, reqData.buffer);
  requestFinished: =>


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
    proxy.on("end", queue.requestFinished);

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
