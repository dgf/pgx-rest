-- calls the generic SQL route function and renders the result

-- requirements
local misc = require("misc")
local cjson = require("cjson.safe")
local rparser = require("rds.parser")

-- get uri, headers, method, ...
local body = "{}" -- default body is empty
local ctype = ngx.req.get_headers().content_type
local method = string.lower(ngx.req.get_method())
local uri = ngx.var.request_uri

-- get mime type and session
local mime = misc.map_mime()
local session_id = misc.check_login(mime)

-- get referer
local referer = ngx.req.get_headers().referer
if not referer or referer == "" then
  referer = "/" -- defaults to index
end

-- content type specific body handling
if method == "post" or method == "put" then

  -- read JSON body
  if ctype == misc.mime_types.json  then
    ngx.req.read_body()
    body = ngx.req.get_body_data() or "{}"

  -- encode HTML form requests
  elseif ctype == misc.mime_types.form then
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
    -- TBD ignore it or throw error?
  end
end

-- create and execute route call query
-- This query construction is secure as long as the application has only access to the "call" route function!
local route_call_sql = "SELECT * FROM call('%s'::text, '%s'::text, %s::uuid, '%s'::json)"
local route_call_query = string.format(route_call_sql, method, uri, session_id, body)
local response = misc.db_capture(route_call_query)

-- update session
local session = misc.update_session(response)

-- return JSON
if mime == "json" then
  ngx.status = response.code
  ngx.print(response.data)

-- check error codes
elseif response.code >= 400 then
  misc.render_error(response)

-- rewrite successful POST requests
elseif method == "post" and response.code < 300 and ctype == misc.mime_types.form then
  local data = cjson.decode(response.data)

  -- use optional response GET route
  if data.routes and data.routes.get then
    ngx.header.location = data.routes.get

  -- or use the original HTTP request referer (fallback)
  else
    ngx.header.location = referer
  end

  ngx.header.content_type = misc.mime_types[mime]
  ngx.status = 303 -- redirect POST response

-- rewrite successful DELETE requests
elseif method == "delete" and response.code < 300 and ctype == misc.mime_types.form then
  local data = cjson.decode(response.data)
  ngx.header.location = data.routes.next

  ngx.header.content_type = misc.mime_types[mime]
  ngx.status = 303 -- redirect DELETE response

-- query and render template
else
  local template_call_sql = "SELECT * FROM find_template('%s'::text, '%s'::text)"
  local template_call_query = string.format(template_call_sql, mime, uri)
  local template = misc.db_capture(template_call_query)

  -- no template found > return JSON
  if template.path == rparser.null then
    ngx.status = response.code
    ngx.print(response.data)

  -- render template with locals, globals and response data
  else
    local value = cjson.decode(template.locals)
    value.data = cjson.decode(response.data)

    -- add session object
    if session and session ~= cjson.null then
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
    ngx.header.content_type = misc.mime_types[mime]
    ngx.status = response.code
    require("resty.template").render(template.path, value)
  end
end

