--OPTIONS--
local SERVER = {"127.0.0.1",3333}
--OPTIONS--

--COMMON--
local PROTOCOL_VERSION = string.char(0x01)
local SEPARATOR = "/"
local MSG_END = "\r\n"
local MSG_CONN = string.char(0x01)
local MSG_STATE = string.char(0x02)
local MSG_SETID = string.char(0x03)
--COMMON--

local socket = assert(socket, "no socket?")

local unpack = unpack or table.unpack

local function run_init(options)
  options = options or {}
  
  local client = assert(socket.connect(
    options.ip or "127.0.0.1",
    options.port or 10000
  ))
  client:settimeout(0)
  client:setoption("keepalive", true)
  client:setoption("tcp-nodelay", true)
  
  client:settimeout(-1)
  client:send(MSG_CONN..PROTOCOL_VERSION..MSG_END)
  for i=1,101 do
    if i == 101 then
      client:close()
      error("\r\n\r\nNo server response!")
    end
    local res = client:receive()
    if (res:sub(1, 1) == MSG_CONN) and ((#res ~= 2) or (res:byte(2) ~= 0)) then
      client:close()
      error(
        ("\r\n\r\nInvalid protocol version!\r\n\r\nClient: v%d\r\nServer: v%s"):format(
          PROTOCOL_VERSION:byte(1),
          (#res == 2) and tostring(res:byte(2)) or "???"
        )
      )
    end
    if (res:sub(1, 1) == MSG_CONN) then
      break
    end
  end
  client:send(MSG_SETID..this:get_id()..MSG_END)
  client:settimeout(0)
  
  return {
    options = options,
    client = client,
    prev_state = {},
  }
end

local function run_step(s, tick)
  local state = {this:read(0), this:read(1), this:read(2), this:read(3)}
  if not s.prev_state[1] then
    s.prev_state = state
  end
  for i=1,4 do
    if s.prev_state[i] ~= state[i] then
      s.prev_state = state
      local state_str = tostring(tick)..SEPARATOR
      for i=1,4 do
        state_str = state_str..("%.7f"):format(state[i])..SEPARATOR
      end
      state_str = state_str:sub(1, -2)
      s.client:send(MSG_STATE..state_str..MSG_END)
      break
    end
  end
end

local function run_principia()
  local state
  function init()
    state = run_init { ip = SERVER[1], port = SERVER[2] }
  end
  function step(count)
    run_step(state, count)
  end
end

run_principia()
