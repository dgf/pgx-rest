-- /upload  POST
local chunk_size = 4096

local misc = require("misc")
local cjson = require("cjson.safe")
local rupload = require("resty.upload")

-- only accept POST request
local method = string.lower(ngx.req.get_method())
if method ~= "post" then
  error("invalid upload call, method: " .. method)
end

-- only accept RFC 1867 request
local ctype = ngx.req.get_headers().content_type
if not starts_with(ctype, "multipart/form-data") then
  error("invalid upload call, content type: " .. ctype)
end

-- extract session ID from cookie string
local session_id = "NULL"
if ngx.var.cookie_session then
  session_id = string.gsub(ngx.var.cookie_session, "(%a+),", "%1")
end

-- create form handler
local form, err = rupload:new(chunk_size)
if not form then
  error("file upload failed: " .. err)
end

-- configure upload time out (milliseconds)
form:set_timeout(1000) -- 1 sec

-- references
local body = {}
local file = {
  name = nil,
  data = nil,
  mime = "application/octet-stream"
}

-- read body chunks
local afield = nil
local avalue = nil
while true do
  local typ, res, err = form:read()
  if err or not typ then
    error("failed to read: " .. err)
  end

  if typ == "header" then

    -- disposition handling
    if res[1] == "Content-Disposition" then

      -- match input name
      afield = res[2]:match("; name=\"([^\"]+)\"")
      if afield == "file" then -- match file name
        file.name = res[2]:match("; filename=\"([^\"]+)\"")
      end

    -- MIME type of file input
    elseif afield == "file" and res[1] == "Content-Type" then
      file.mime = res[2]

    else
      error("unsupported header: " .. cjson.encode(res))
    end

  elseif typ == "body" then
    if avalue == nil then
      avalue = res
    else
      avalue = avalue .. res
    end

  elseif typ == "part_end" then
    if afield == "file" then
      file.data = ngx.encode_base64(avalue)
    else
      body[afield] = avalue
    end
    afield = nil
    avalue = nil

  elseif typ == "eof" then
    break

  else
    error("unsupported form part: " .. cjson.encode(typ))
  end
end

-- create file
if session_id ~= "NULL" then session_id = "'" .. session_id .. "'" end
local sql = "SELECT * FROM upload(%s::uuid, '%s'::text, '%s'::text, '%s'::text, '%s'::text)"
local query = string.format(sql, session_id, file.name, file.mime, body.description, file.data)
local response = misc.capture(query)

-- upload failed
if response.code ~= 201 then
  if string.find(ngx.req.get_headers().accept, "text/html") then
    misc.error(response)
  else -- return JSON
    ngx.status = response.code
    ngx.print(response.session)
    ngx.print(response.data)
  end

-- uploaded
else
  -- update session
  local session = cjson.decode(response.session)
  ngx.header["Set-Cookie"] = "session=" .. session.id .. "; Path=/; Expires=" .. ngx.cookie_time(session.epoch)

  -- redirect to file resource
  ngx.status = 303
  local data = cjson.decode(response.data)
  ngx.header.location = data.routes.get
end

