-- calls the generic SQL route function and renders the result

-- requirements
local misc = require("misc")
local cjson = require("cjson.safe")
local rparser = require("rds.parser")
local rtemplate = require("resty.template")

-- configuration
local mime_types = {
  form = "application/x-www-form-urlencoded",
  html = "text/html",
  json = "application/json",
  svg = "image/svg+xml"
}

-- get uri, headers, method, ...
local accept = ngx.req.get_headers().accept
local body = "{}" -- default body is empty
local ctype = ngx.req.get_headers().content_type
local method = string.lower(ngx.req.get_method())
local referer = ngx.req.get_headers().referer
local uri = ngx.var.request_uri

-- fix referer
if not referer or referer == "" then
  referer = "/" -- defaults to index page
end

-- content type specific body handling
if method == "post" or method == "put" then

  -- read JSON body
  if ctype == mime_types.json  then
    ngx.req.read_body()
    body = ngx.req.get_body_data()

  -- encode HTML form requests
  elseif ctype == mime_types.form then
    ngx.req.read_body()
    local pargs = ngx.req.get_post_args()
    body = cjson.encode(pargs)

    -- use optional hidden input 'back' value as referer
    if pargs.back then
      referer = pargs.back
    end

    -- rewrite request with hidden input 'method' value
    if method == "post" and (pargs.method == "put" or pargs.method == "delete") then
      method = pargs.method -- change request method
    end

  -- unsupported call, e.g. post multipart/form-data
  else
    -- ignore it
  end
end

-- test mime type
local mime = "json" -- default accept mime is JSON
if string.find(accept, mime_types.html) then mime = 'html' end
if string.find(accept, mime_types.svg) then mime = 'svg' end

-- extract session ID from cookie string
local session_id = "NULL"
if ngx.var.cookie_session then
  session_id = string.gsub(ngx.var.cookie_session, "(%a+),", "%1")
end

-- HTTP basic auth request
if session_id == "NULL" and ngx.var.remote_user then

  -- query login function
  local auth_sql = "SELECT * FROM login('%s'::text, '%s'::text)"
  local password64b = string.gsub(ngx.var.http_authorization, "Basic (%a+)", "%1")
  local auth_query = string.format(auth_sql, ngx.var.remote_user, password64b)
  local auth_response = misc.capture(auth_query)

  -- login failed
  if auth_response.code ~= 200 then
    if mime == "json" then
      ngx.status = auth_response.code
      ngx.print(auth_response.data)
    else
      misc.error(auth_response)
    end
    ngx.exit(auth_response.code)

  -- authenticated
  else
    local auth_session = cjson.decode(auth_response.session)
    session_id = auth_session.id -- reassign session ID
  end
end

-- create and execute route call query
-- This query construction is secure as long as the application has only access to the "call" route function!
if session_id ~= "NULL" then session_id = "'" .. session_id .. "'" end
local route_call_sql = "SELECT * FROM call('%s'::text, '%s'::text, %s::uuid, '%s'::json)"
local route_call_query = string.format(route_call_sql, method, uri, session_id, body)
local response = misc.capture(route_call_query)

-- update session cookie
local session = cjson.decode(response.session)
if session and session ~= cjson.null then
  ngx.header["Set-Cookie"] = "session=" .. session.id .. "; Path=/; Expires=" .. ngx.cookie_time(session.epoch)
else -- invalidate session
  ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())
end

-- return JSON
if mime == "json" then
  ngx.status = response.code
  ngx.print(response.data)

-- check error codes
elseif response.code >= 400 then
  misc.error(response)

-- rewrite successful POST requests
elseif method == "post" and response.code < 300 and ctype == mime_types.form then
  local data = cjson.decode(response.data)
  ngx.status = 303 -- redirect POST response

  -- use optional response GET route
  if data.routes and data.routes.get then
    ngx.header.location = data.routes.get

  -- or use the original HTTP request referer (fallback)
  else
    ngx.header.location = referer
  end

-- rewrite successful DELETE requests
elseif method == "delete" and response.code < 300 and ctype == mime_types.form then
  local data = cjson.decode(response.data)
  ngx.status = 303 -- redirect DELETE response
  ngx.header.location = data.routes.next

-- query and render template
else
  local template_call_sql = "SELECT * FROM find_template('%s'::text, '%s'::text)"
  local template_call_query = string.format(template_call_sql, mime, uri)
  local template = misc.capture(template_call_query)

  -- no template found > return JSON
  if template.path == rparser.null then
    ngx.status = response.code
    ngx.print(response.data)

  -- render template with locals, globals and response data
  else
    local value = cjson.decode(template.locals)
    value.data = cjson.decode(response.data)

    -- add session object
    if session ~= cjson.null then
      value.session = session
    end

    -- add application globals
    local globals = cjson.decode(response.globals)
    if globals and globals ~= cjson.null then
      value.globals = globals
    end

    -- add referer as back route
    if value.data.routes then
      value.data.routes.back = referer
    else -- create a new route list
      value.data.routes = { back = referer }
    end

    -- set headers and render template
    ngx.header.content_type = mime_types[mime]
    ngx.status = response.code
    rtemplate.render(template.path, value)
  end
end

