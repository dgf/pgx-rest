-- /logout POST
local misc = require("misc")
local rparser = require("rds.parser")

-- only accept an authenticated POST request
if string.lower(ngx.req.get_method()) ~= "post" then
  error("invalid logout method")
elseif not ngx.var.cookie_session then
  error("invalid logout session")
end

-- query logout function
local session = string.gsub(ngx.var.cookie_session, "(%a+),", "%1")
local sql = "SELECT * FROM post_logout('%s'::uuid)"
local query = string.format(sql, session)
local response = misc.capture(query)

-- return JSON
if string.find(ngx.req.get_headers().accept, "application/json") then
  ngx.status = response.code
  ngx.print(response.data)

-- redirect successful HTML logout
elseif response.code == 200 then
  -- invalidate cookie
  ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())
  -- redirect to login form
  ngx.status = 303
  ngx.header.location = "/login"

-- logout failed, render HTML error page
else 
  misc.error(response)
end

