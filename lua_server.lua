--COMMON--
local PROTOCOL_VERSION = string.char(0x01)
local SEPARATOR = "/"
local MSG_END = "\r\n"
local MSG_CONN = string.char(0x01)
local MSG_STATE = string.char(0x02)
local MSG_SETID = string.char(0x03)
--COMMON--

local socket = require "socket"

local function run(options)
  options = options or {}
  
  print("pmp server starting")
  print(socket._VERSION)
  
  local ip, port = options.ip or "*", options.port or 10000
  print(("binding %s:%d"):format(ip, port))
  local server = assert(socket.bind(ip, port))
  server:settimeout(0)
  server:setoption("keepalive", true)
  server:setoption("tcp-nodelay", true)
  print(("running on tcp %s:%d"):format(server:getsockname()))
  
  local clients = {}
  local sock_client_map = {}
  
  local function drop_client_by_conn(conn)
    assert(sock_client_map[conn], "client doesnt exist")
    print("disconnecting client id "..sock_client_map[conn].id)
    conn:close()
    table.remove(clients, sock_client_map[conn].id)
    sock_client_map[conn] = nil
    for i, client in ipairs(clients) do
      if client.id ~= i then
        print(("client %d is now %d"):format(client.id, i))
        client.id = i
      end
    end
  end

  while true do
    local select_clients = {server}
    for i, client in ipairs(clients) do
      select_clients[i + 1] = assert(client.sock, "client has no sock")
    end
    local ready, _, err = socket.select(select_clients)
    if ready then
      for _, conn in ipairs(ready) do
        if conn == server then
          local client = conn:accept()
          client:settimeout(1)
          if client then
            clients[#clients+1] = {
              sock = client
            }
            sock_client_map[client] = clients[#clients]
            clients[#clients].id = #clients
            print(("client %d connected"):format(#clients))
          end
        else
          local msg, err = conn:receive()
          local client = sock_client_map[conn]
          if msg then
            if msg:sub(1, 1) == MSG_CONN then
              if (#msg ~= 2) or (msg:sub(2, 2) ~= PROTOCOL_VERSION) then
                print("invalid protocol version: "..((#msg == 2) and msg:byte(2) or "???"))
                conn:send(MSG_CONN..PROTOCOL_VERSION..MSG_END)
                drop_client_by_conn(conn)
              else
                print("client protocol version verified")
                conn:send(MSG_CONN..string.char(0)..MSG_END)
              end
            elseif msg:sub(1, 1) == MSG_SETID then
              client.ctrl_id = tonumber(msg:sub(2, -1))
              print(("client %d updated it's controller id: %d"):format(client.id, client.ctrl_id))
              --TODO: Check if another client has the same id
            elseif msg:sub(1, 1) == MSG_STATE then
              print("value changed")
              print(msg:sub(2, -1))
              for _, client in ipairs(clients) do
                client.sock:send(msg..MSG_END)
              end
            else
              print("???")
            end
          elseif err then
            print(("recv error: %s"):format(msg))
            drop_client_by_conn(conn)
          end
        end
      end
    elseif err then
      print(("error: %s"):format(err))
    end
  end
end

run { ip = "127.0.0.1", port = 3333 }

--local msg, err = client:receive()
        
        