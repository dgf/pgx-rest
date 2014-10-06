-- calls the generic SQL route function and renders the result

-- requirements
local misc = require("misc")
local cjson = require("cjson.safe")
local rparser = require("rds.parser")
local rtemplate = require("resty.template")

-- configuration
local mime_types = {
  html = "text/html",
  svg = "image/svg+xml"
}

-- get uri, query, method, args, ...
local uri = ngx.var.request_uri
local referer = ngx.req.get_headers().referer
local ctype = ngx.req.get_headers().content_type
local accept = ngx.req.get_headers().accept
local method = string.lower(ngx.req.get_method())
local pargs = ngx.req.get_post_args()
local body = ngx.req.get_body_data()

-- test mime type
local mime = "json"
if string.find(accept, mime_types.html) then mime = 'html' end
if string.find(accept, mime_types.svg) then mime = 'svg' end

-- encode HTML form requests
if ctype == "application/x-www-form-urlencoded" then
  body = cjson.encode(pargs)

  -- rewrite HTTP POST request to route method (only PUT and DELETE)
  if method == "post" and (pargs.method == "put" or pargs.method == "delete") then
    method = pargs.method -- change request method
  end
end

-- fix empty request body
if not body then body = "{}" end

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
local route_call_sql = "SELECT * FROM call('%s'::method, '%s'::text, %s::uuid, '%s'::json)"
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
elseif method == "post" and response.code < 300 and ctype == "application/x-www-form-urlencoded" then
  local data = cjson.decode(response.data)
  ngx.status = 303 -- redirect POST response

  -- use optional hidden input 'back' value
  if pargs.back then
    ngx.header.location = pargs.back

  -- or use optional response GET route
  elseif data.routes and data.routes.get then
    ngx.header.location = data.routes.get

  -- or the original HTTP request referer (fallback)
  else
    ngx.header.location = referer
  end

-- rewrite successful DELETE requests
elseif method == "delete" and response.code < 300 and ctype == "application/x-www-form-urlencoded" then
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

  -- render template with locals and response data
  else
    local value = cjson.decode(template.locals)
    value.data = cjson.decode(response.data)
    if session ~= cjson.null then
      value.session = session
    end

    -- add the back route action
    if not referer or referer == "" then
      referer = "/"
    end
    if value.data.routes then
      value.data.routes.back = referer
    else
      value.data.routes = { back = referer }
    end

    -- set headers and render template
    ngx.header.content_type = mime_types[mime]
    ngx.status = response.code
    rtemplate.render(template.path, value)
  end
end

