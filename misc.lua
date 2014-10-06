-- misc interactions

-- requirements
local cjson = require("cjson.safe")
local rparser = require("rds.parser")
local rtemplate = require("resty.template")

-- HTML error response
function render_error(response)
  ngx.status = response.code
  ngx.header.content_type = "text/html"

  -- invalidate cookie
  if response.code == 401 then
    -- do not request the Browser login dialog
    -- ngx.header.www_authenticate = "Basic realm=Login"
    ngx.header["Set-Cookie"] = "session=NULL; Path=/; Expires=" .. ngx.cookie_time(ngx.time())
  end

  -- render error page
  local value = { title = response.code .. " Error" }
  local rsession = cjson.decode(response.session)
  if rsession and rsession ~= cjson.null then
    value.session = rsession
  end
  local rerror = cjson.decode(response.data)
  if rerror ~= cjson.null then
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

-- export misc functions
return {
  capture = db_capture,
  error = render_error
}

