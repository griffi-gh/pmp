--OPTIONS--
local SERVER = {"127.0.0.1",3333}
--OPTIONS--

--COMMON--
local PROTOCOL_VERSION = string.char(0x01)
local BUCKET_SIZE = 120
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
    dead = false,
    options = options,
    client = client,
    next_state = nil,
    prev_state = nil,
    state = nil,
    out_state = {0,0,0,0},
  }
end

local function run_step(s, tick)
  if s.dead then return end
  --Check messages
  local msg, err = s.client:receive()
  if msg then
    if msg:sub(1, 1) == MSG_STATE then
      local tokens = {}
      for token in msg:sub(2,-1):gmatch("[^/]+") do
        tokens[#tokens + 1] = tonumber(token)
      end
      local change_tick = tokens[1]
      table.remove(tokens, 1)
      if math.floor(change_tick / BUCKET_SIZE) ~= math.floor(tick / BUCKET_SIZE) then
        --s.dead = true
        --error("Client time out of sync")
        return
      end
      s.next_state = tokens
    else
      error("Unsupported message")
    end
  end
  
  --Get current state
  local state = {this:read(0), this:read(1), this:read(2), this:read(3)}
  
  --if prev_state is nil, just set it to the current state
  if not s.prev_state then
    s.prev_state = state
  end
  
  --send updates
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
  
  --detect bucket change and apply next state
  if (tick % (BUCKET_SIZE + 1)) == 0 then
    if s.next_state then
      s.out_state, s.prev_state, s.next_state = s.next_state, s.next_state, nil
    end
  end
  
  --write output
  this:write(0, s.out_state[1])
  this:write(1, s.out_state[2])
  this:write(2, s.out_state[3])
  this:write(3, s.out_state[4])
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
