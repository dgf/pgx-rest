-- /download GET
local misc = require("misc")
local cjson = require("cjson.safe")

-- only accept GET request
local method = string.lower(ngx.req.get_method())
if method ~= "get" then
  error("invalid upload call, method: " .. method)
end

-- extract session ID from cookie string
local session_id = "NULL"
if ngx.var.cookie_session then
  session_id = string.gsub(ngx.var.cookie_session, "(%a+),", "%1")
end

-- query file
if session_id ~= "NULL" then session_id = "'" .. session_id .. "'" end
local sql = "SELECT * FROM download(%s::uuid, '%s'::int)"
local query = string.format(sql, session_id, ngx.var.file_id)
local response = misc.capture(query)

-- download failed
if response.code ~= 200 then
  if string.find(ngx.req.get_headers().accept, "text/html") then
    misc.error(response)
  else -- return JSON
    ngx.header["Content-Type"] = misc.mime_types.json
    ngx.status = response.code
    ngx.print(response.session)
    ngx.print(response.data)
  end

-- send file
else
  local data = cjson.decode(response.data)
  ngx.status = response.code
  ngx.header["Content-Disposition"] = "attachment; filename=" .. data.name
  ngx.header["Content-Type"] = data.mime
  ngx.say(ngx.decode_base64(data.data))
end
