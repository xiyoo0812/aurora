--protobuf_mgr.lua

require("pb.init")

local pcall         = pcall
local pairs         = pairs
local ipairs        = ipairs
local pb_enum_id    = pb.enum
local pb_decode     = pb.decode
local pb_encode     = pb.encode
local log_err       = logger.err
local log_warn      = logger.warn
local supper        = string.upper
local ssplit        = qstring.split
local sends_with    = qstring.ends_with
local dgetinfo      = debug.getinfo
local setmetatable  = setmetatable

local Pprotobuf = singleton()
local prop = property(Pprotobuf)
prop:reader("pb_names", {})
prop:reader("pb_indexs", {})
prop:reader("pb_callbacks", {})
prop:reader("allow_reload", false)

function Pprotobuf:__init()
	self:load_pbfile("proto/ncmd_cs.pb")
end

--返回回调id
function Pprotobuf:callback_id(cmd_id)
	local pb_cbid = self.pb_callbacks[cmd_id]
	if not pb_cbid then
		print("[Pprotobuf][callback_id] cmdid {} find callback_id is nil", cmd_id)
	end
	return pb_cbid
end

--返回协议名称
function Pprotobuf:msg_name(pb_cmd)
	return self.pb_indexs[pb_cmd].name
end

function Pprotobuf:msg_id(pb_cmd)
	return self.pb_indexs[pb_cmd].id
end

function Pprotobuf:error_code(err_key)
	return self:enum("ErrorCode", err_key)
end

function Pprotobuf:enum(ename, ekey)
	local emun = ncmd_cs[ename]
	if not emun then
		local info = dgetinfo(2, "S")
		log_warn("[Pprotobuf][enum] {} not initial! source({}:{})", ename, info.short_src, info.linedefined)
		return
	end
	local value = emun[ekey]
	if not value then
		local info = dgetinfo(2, "S")
		log_warn("[Pprotobuf][enum] %s.%s not defined! source({}:{})", ename, ekey, info.short_src, info.linedefined)
		return
	end
	return value
end

--加载pb文件
function Pprotobuf:load_pbfile(pb_file)
	--加载PB文件
	pb.loadfile(pb_file)
	--设置枚举解析成number
	--pb.option("enum_as_value")
	--pb.option("encode_default_values")
	--注册枚举
	for name, _, typ in pb.types() do
		if typ == "enum" then
			self:define_enum(name)
		end
	end
	--注册CMDID和PB的映射
	for name, basename, typ in pb.types() do
		if typ == "message" then
			self:define_command(name, basename)
		end
	end
end

function Pprotobuf:encode_byname(pb_name, data)
	local ok, pb_str = pcall(pb_encode, pb_name, data or {})
	if ok then
		return pb_str
	end
end

function Pprotobuf:encode(pb_cmd, data)
	local proto = self.pb_indexs[pb_cmd]
	if not proto then
		log_err("[Pprotobuf][encode] find proto failed! cmd:{}", pb_cmd)
		return
	end
	local ok, pb_str = pcall(pb_encode, proto.name, data or {})
	if ok then
		return pb_str, proto.id
	end
end

function Pprotobuf:decode_byname(pb_name, pb_str)
	local ok, pb_data = pcall(pb_decode, pb_name, pb_str)
	if ok then
		return pb_data
	end
end

function Pprotobuf:decode(pb_cmd, pb_str)
	local proto = self.pb_indexs[pb_cmd]
	if not proto then
		log_err("[Pprotobuf][decode] find proto failed! cmd:{}", pb_cmd)
		return
	end
	local ok, pb_data = pcall(pb_decode, proto.name, pb_str)
	if ok then
		return pb_data, proto.name
	end
end

local function pbenum(full_name)
	return function(_, enum_name)
		local enum_val = pb_enum_id(full_name, enum_name)
		if not enum_val then
			log_warn("[pbenum] no enum {}.{}", full_name, enum_name)
		end
		return enum_val
	end
end

function Pprotobuf:define_enum(full_name)
	local pb_enum = _G
	local nodes = ssplit(full_name, ".")
	for _, name in ipairs(nodes) do
		if not pb_enum[name] then
			pb_enum[name] = {}
		end
		pb_enum = pb_enum[name]
	end
	setmetatable(pb_enum, {__index = pbenum(full_name)})
end

function Pprotobuf:define_command(full_name, proto_name)
	local proto_isreq = sends_with(proto_name, "_req")
	if proto_isreq or sends_with(proto_name, "_res") or sends_with(proto_name, "_ntf") then
		local package_name = unpack(ssplit(full_name, "."))
		local msg_name = "NID_" .. supper(proto_name)
		local enum_type = package_name .. ".NCmdId"
		local msg_id = pb_enum_id(enum_type, msg_name)
		if msg_id then
			self.pb_names[msg_id] = msg_name
			self.pb_indexs[msg_id] = { id = msg_id, name = full_name }
			self.pb_indexs[msg_name] = { id = msg_id, name = full_name }
			if proto_isreq then
				local msg_res_name = msg_name:sub(0, -2) .. "S"
				local msg_res_id = pb_enum_id(enum_type, msg_res_name)
				if msg_res_id then
					self.pb_callbacks[msg_id] = msg_res_id
				end
			end
			return
		end
		log_warn("[Pprotobuf][define_command] proto_name: [{}] can't find msg enum:[{}] !", proto_name, msg_name)
	end
end

function Pprotobuf:register(doer, pb_name, callback)
	local proto = self.pb_indexs[pb_name]
	if not proto then
		log_warn("[Pprotobuf][register] proto_name: [{}] can't find!", pb_name)
		return
	end
	listener:add_cmd_listener(doer, proto.id, callback)
end

protobuf = Pprotobuf()

return Pprotobuf