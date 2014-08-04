-- calls the generic SQL route function

-- get uri, query, method and fix body
local method = string.lower(ngx.req.get_method())
local uri = ngx.var.uri
local args = ngx.encode_args(ngx.req.get_uri_args())
local body = ngx.req.get_body_data()
if args and #args > 2 then uri = uri .. '?' .. args end
if not body then body = '{}' end

-- create and execute query
local sql = "SELECT * FROM call('%s'::method, '%s'::text, '%s'::json)"
local query = string.format(sql, method, uri, body)
local result = ngx.location.capture("/query", { body = query })
if result.status ~= ngx.HTTP_OK or not result.body then error("failed to query database") end

-- parse query result
local parser = require("rds.parser")
local body, err = parser.parse(result.body)
if not body then error("failed to parse RDS: " .. err) end

-- validate result set
local rows = body.resultset
if not rows or #rows ~= 1 then error("something went wrong") end

-- set response status and output data
local response = rows[1]
ngx.status = response.code
if response.data ~= parser.null then ngx.print(response.data) end

