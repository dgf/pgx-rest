-- /download GET
local misc = require("misc")
local cjson = require("cjson.safe")

-- only accept GET request
local method = string.lower(ngx.req.get_method())
if method ~= "get" then
  error("invalid download call, method: " .. method)
end

-- login check
local session_id = misc.check_login(mime)

-- query file
local sql = "SELECT * FROM download(%s::uuid, '%s'::int)"
local query = string.format(sql, session_id, ngx.var.file_id)
local response = misc.db_capture(query)

-- download failed
if response.code ~= 200 then

  -- HTML response
  if string.find(ngx.req.get_headers().accept, misc.mime_types.html) then
    misc.render_error(response)

  -- return JSON
  else
    ngx.status = response.code
    ngx.print(response.data)
  end

-- send file
else
  local data = cjson.decode(response.data)
  ngx.header["Content-Disposition"] = "attachment; filename=" .. data.name
  ngx.header["Content-Type"] = data.mime
  ngx.status = response.code
  ngx.say(ngx.decode_base64(data.data))
end
