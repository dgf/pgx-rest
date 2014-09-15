-- calls the generic SQL route function and renders the result

-- requirements
local template = require "resty.template"
local cjson = require "cjson.safe"
local mime_types = {
  html = "text/html",
  svg = "image/svg+xml"
}

-- get uri, query, method, args, ...
local uri = ngx.var.uri
local referer = ngx.req.get_headers().referer
local ctype = ngx.req.get_headers().content_type
local accept = ngx.req.get_headers().accept
local method = string.lower(ngx.req.get_method())
local pargs = ngx.req.get_post_args()
local body = ngx.req.get_body_data()

-- concat uri args
local args = ngx.encode_args(ngx.req.get_uri_args())
if args and #args > 2 then uri = uri .. "?" .. args end

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

-- create and execute route call query
-- this query construction is secure as long as the user has only access to the "call" route function
local sql = "SELECT * FROM call('%s'::method, '%s'::text, '%s'::json)"
local query = string.format(sql, method, uri, body)
local result = ngx.location.capture("/query", { body = query })
if result.status ~= ngx.HTTP_OK or not result.body then error("route call failed") end

-- parse query result
local parser = require("rds.parser")
local body, err = parser.parse(result.body)
if not body then error("invalid RDS body: " .. err) end

-- validate result set
local rows = body.resultset
if not rows or #rows ~= 1 then error("something went wrong") end

-- render a template or return JSON response
local response = rows[1]
if response.data ~= parser.null then

  -- test mime type
  local mime = "json"
  if string.find(accept, mime_types.html) then mime = 'html' end
  if string.find(accept, mime_types.svg) then mime = 'svg' end

  -- return JSON
  if mime == "json" then
    ngx.status = response.code
    ngx.print(response.data)

  -- check error codes
  elseif response.code >= 400 then
    ngx.status = response.code
    local value = { title = response.code .. " Error" }
    value.error = cjson.decode(response.data)
    ngx.header.content_type = mime_types.html
    template.render("error.html", value)

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

    -- or the original referer (fallback)
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
    sql = "SELECT * FROM find_template('%s'::text, '%s'::text)"
    query = string.format(sql, mime, uri)
    result = ngx.location.capture("/query", { body = query })
    body, err = parser.parse(result.body)
    local path = cjson.null
    if body and body.resultset and #body.resultset == 1 then
      path = body.resultset[1].path
    end

    -- no template found > return JSON
    if path == cjson.null then
      ngx.status = response.code
      ngx.print(response.data)

    -- render template with locals and response data
    else
      local value = cjson.decode(body.resultset[1].locals)
      value.data = cjson.decode(response.data)

      -- add the back route action
      if value.data.routes then
        value.data.routes.back = referer
      else
        value.data.routes = { back = referer }
      end

      -- set headers and render template
      ngx.header.content_type = mime_types[mime]
      ngx.status = response.code
      template.render(path, value)
    end
  end
end

