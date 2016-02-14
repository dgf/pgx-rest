-- /logout POST

-- requirements
local misc = require("misc")
local rparser = require("rds.parser")

-- get mime type and session
local mime = misc.map_mime()
local session_id = misc.check_login(mime)

-- only accept an authenticated POST request
if string.lower(ngx.req.get_method()) ~= "post" then
  error("invalid logout call, method: " .. ngx.req.get_method())
elseif not ngx.var.cookie_session then
  error("invalid logout session")
end

-- query logout function
local sql = "SELECT * FROM post_logout(%s::uuid)"
local query = string.format(sql, session_id)
local response = misc.db_capture(query)

-- return JSON
if mime == "json" then
  ngx.status = response.code
  ngx.print(response.data)

-- logout failed, render HTML error page
elseif response.code ~= 200 then
  misc.render_error(response)

-- redirect successful HTML logout
else

  -- invalidate cookie
  ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())

  -- redirect to login form
  ngx.status = 303
  ngx.header.content_type = misc.mime_types.html
  ngx.header.location = "/login"
end

