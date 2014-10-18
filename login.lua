-- /authenticate POST
local misc = require("misc")
local cjson = require("cjson.safe")
local rparser = require("rds.parser")

-- only accept POST request
if string.lower(ngx.req.get_method()) ~= "post" then
  error("invalid login call, method: " .. ngx.req.get_method())
end

-- get POST args or body data
ngx.req.read_body()
local body = ngx.req.get_post_args()
if ngx.req.get_headers().content_type ~= "application/x-www-form-urlencoded" then
  body = ngx.req.get_body_data()
end

-- query login function (with plain password)
local sql = "SELECT * FROM post_login('%s'::text, '%s'::text)"
local query = string.format(sql, body.login, body.password)
local response = misc.capture(query)

-- login failed
if response.code ~= 200 then
  if string.find(ngx.req.get_headers().accept, "text/html") then
    misc.error(response)
  else -- return JSON
    ngx.status = response.code
    ngx.print(response.session)
    ngx.print(response.data)
  end

-- authenticated
else
  -- create session cookie
  local session = cjson.decode(response.session)
  ngx.header["Set-Cookie"] = "session=" .. session.id .. "; Path=/; Expires=" .. ngx.cookie_time(session.epoch)

  -- return JSON
  if string.find(ngx.req.get_headers().accept, "application/json") then
    ngx.status = response.code
    ngx.print(response.data)

  else
    -- use HTTP referer or hidden back param
    local referer = ngx.req.get_headers().referer
    if body.back then
      referer = body.back
    end

    -- redirect back
    ngx.status = 303
    ngx.header.location = referer
  end
end

