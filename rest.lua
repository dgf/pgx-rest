-- calls the generic SQL route function and renders the result

-- requirements
local template = require "resty.template"
local cjson = require "cjson.safe"
local mime_types = {
  html = "text/html",
  svg = "image/svg+xml"
}

-- get uri, query, method and fix body
local uri = ngx.var.uri
local ctype = ngx.req.get_headers().content_type
local accept = ngx.req.get_headers().accept
local method = string.lower(ngx.req.get_method())
local args = ngx.encode_args(ngx.req.get_uri_args())
local body = ngx.req.get_body_data()
if args and #args > 2 then uri = uri .. "?" .. args end

-- encode HTML form requests and rewrite HTTP POST request to route method (only PUT)
if ctype == "application/x-www-form-urlencoded" then
  local pargs = ngx.req.get_post_args()
  body = cjson.encode(pargs)
  if method == "post" and pargs.method then
    method = "put" -- change request method
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
  elseif response.code == 201 and ctype == "application/x-www-form-urlencoded" then
      local entitiy = cjson.decode(response.data)
      ngx.status = 303 -- redirect POST response
      ngx.header.location = entitiy.routes.get

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
    if path == cjson.null then -- no template found > return JSON
      ngx.status = response.code
      ngx.print(response.data)
    else -- render template with locals and response data
      local value = cjson.decode(body.resultset[1].locals)
      value.data = cjson.decode(response.data)
      ngx.header.content_type = mime_types[mime]
      ngx.status = response.code
      template.render(path, value)
    end
  end
end

