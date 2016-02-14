-- misc interactions

-- requirements
local cjson = require("cjson.safe")
local rparser = require("rds.parser")
local rtemplate = require("resty.template")

local mime_types = { -- TBD merge and read mime.types
  form = "application/x-www-form-urlencoded",
  html = "text/html",
  json = "application/json",
  svg = "image/svg+xml"
}

-- map accept content type, defaults to json
function map_mime()
  local accept = ngx.req.get_headers().accept
  local mime = "json" -- default accept mime is JSON
  if string.find(accept, mime_types.html) then
    mime = 'html'
  elseif string.find(accept, mime_types.svg) then
    mime = 'svg'
  end
  return mime
end

-- string helper, starts with?
function starts_with(string, start)
  return string.sub(string, 1, string.len(start)) == start
end

-- HTML error response
function render_error(response)
  ngx.status = response.code
  ngx.header.content_type = mime_types.html

  -- invalidate cookie
  if response.code == 401 then
    -- do not request the Browser login dialog
    -- ngx.header.www_authenticate = "Basic realm=Login"
    ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())
  end

  -- render error page
  local globals = cjson.decode(response.globals)
  local session = cjson.decode(response.session)
  local rerror = cjson.decode(response.data)
  local value = { title = response.code .. " Error" }
  if session and session ~= cjson.null then
    value.session = session
  end
  if globals and globals ~= cjson.null then
    value.globals = globals
  end
  if rerror and rerror ~= cjson.null then
    value.error = rerror
  end
  rtemplate.render("error.html", value)
end

-- capture and validate a database query
function db_capture(query)
  local result = ngx.location.capture("/query", { body = query })

  -- validate location result
  if result.status ~= ngx.HTTP_OK or not result.body then
    error("database query failed: " .. query)
  end

  -- parse query result
  local body, err = rparser.parse(result.body)
  if err then
    error("invalid RDS response: " .. err)
  end

  -- validate result set
  if not body.resultset or #body.resultset ~= 1 then
    error("invalid resultset")
  end

  -- return response
  return body.resultset[1]
end

-- login
function check_login(mime)

  -- extract session ID from cookie string
  local session_id = "NULL"
  if ngx.var.cookie_session then
    session_id = string.gsub(ngx.var.cookie_session, "(%a+),", "%1")
  end

  -- HTTP basic auth request check
  if session_id == "NULL" and ngx.var.remote_user then

    -- query login function
    local auth_sql = "SELECT * FROM login('%s'::text, '%s'::text)"
    local password64b = string.gsub(ngx.var.http_authorization, "Basic (%a+)", "%1")
    local auth_query = string.format(auth_sql, ngx.var.remote_user, password64b)
    local auth_response = db_capture(auth_query)

    -- login failed
    if auth_response.code ~= 200 then
      if mime == "json" then
        ngx.print(auth_response.data)
      else
        render_error(auth_response)
      end
      ngx.exit(auth_response.code)

    -- authenticated
    else
      local auth_session = cjson.decode(auth_response.session)
      session_id = auth_session.id -- reassign session ID
    end
  end

  -- return actual session
  if session_id ~= "NULL" then session_id = "'" .. session_id .. "'" end
  return session_id
end

-- update session cookie
function update_session(response)
  local session = cjson.decode(response.session)
  if session and session ~= cjson.null then
    ngx.header["Set-Cookie"] = "session=" .. session.id .. "; Path=/; Expires=" .. ngx.cookie_time(session.epoch)
  else -- invalidate session
    ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())
  end
  return session
end

-- export misc functions and configuration
return {
  check_login = check_login,
  db_capture = db_capture,
  map_mime = map_mime,
  mime_types = mime_types,
  render_error = render_error,
  starts_with = starts_with,
  update_session = update_session
}

