WIFI=1
LATEST=2
MQTT=3
CAN_PUBLISH=4
INIT=5
CAN_DISTANCE=6
CAN_TEMP=7
-- FIXME: read timers and other config from config file
WATCHDOG=300000

--FIXME1: when to store status in rtcmem.write and load as prior last status

--FIXME2: improve log handling: ability to suppress debug

status=0
dog=tmr.softwd(WATCHDOG)

topic,_=string.gsub(wifi.sta.getmac(), ":","")
_ = nil
mq=mqtt.Client(topic, 120)
topic="/esp/"..topic
lstack ={}
srv=net.createServer(net.TCP)

tsensor=nil
sensor={}

function init_finished()
    status=bit.set(status, INIT)
    startup = nil
    dofile("garager.lua")
end

function update_sensor()
    sensor.memtot, sensor.memused = node.egc.meminfo()
    sensor.heap = node.heap()
    sensor.status = status
    local str=""
    if lstack[1] then
        str = lstack[1]
    end
    sensor.lastlog = str
end

function log(str)
    table.insert(lstack, str)
    print(str)
    update_sensor()
    --FIXME2: error handling here?
    local function send_log()
        mq:publish(topic.."/log", sjson.encode(sensor),0,0, function(client)
            status=bit.set(status, CAN_PUBLISH)
            table.remove(lstack, 1)            
        end)
    end
        -- try to send other pending log messages
    if #lstack > 0 then
        send_log()
    end
end

function startup()
    if not bit.isset(status, WIFI) then
        if wifi.sta.status() == wifi.STA_GOTIP then
            status=bit.set(status, WIFI)
            print("WiFi IP: ", wifi.sta.getip())
        else
            print("waiting for IP")
        end
        tmr.alarm(0,200,0, startup)
    else
        if pcall(init_temp) then
            print("loaded ds18b20 module")
            status=bit.set(status, CAN_TEMP)
            init_temp=nil
        else
            log("couldn't load ds18b20 module")
        end    
        srv=net.createServer(net.TCP)
        srv:listen(81, srv_message)
        --FIXME: add srv to status bitmask?
        print("backdoor srv started")
        if not bit.isset(status, MQTT) then
            mq:lwt(topic.."/available", "offline", 2)
            mqtt_connect()
        end
    end
end

function update()
    -- FIXME: Updater logic!
    http.get("http://192.168.1.85"..topic.."/updater.lua", nil, function(code, data)
        if (code ~= 200) then
            log("Updater HTTP request failed")
        else
            log("Updater: "..code)
            fd = file.open("updater.lua", "w")
            if fd then
              fd:write(data)
              fd:close()
              -- FIXME1: pcall error handling
              f=loadfile("updater.lua")
              f()
              status=bit.set(status, LATEST)
              log("updater ran successfully")
            else
                log('could not write or run updater file')
            end
        end
    end)
end

function mqtt_connect()
    print("connecting to MQTT")
    if pcall(mq:connect("192.168.1.31", 1883, 0, 0, function(conn)
        log(lastmsg)
        print ("Connected to MQTT")
        mq:publish(topic.."/available", "online",1,0)
        conn:subscribe(topic.."/command", 0, function(client) 
            log("subscribe success") 
        end)
        status=bit.set(status, MQTT)
        dog=tmr.softwd(WATCHDOG)
        if not bit.isset(status, INIT) then
            init_finished()
        end
    end)) then
        log ("unexpected mqtt error, trying again in 5 sec")
        tmr.alarm(0,5000,0,mqtt_connect)
    end
end

mq:on("offline", function(client) 
    --print ("MQTToffline")
    status=bit.clear(status, MQTT) 
    log("reconnecting mqtt")
    tmr.alarm(0,1000,0,mqtt_connect)
end)

mq:on("message", function(client, topic, data) 
    print(topic .. ": " ) 
    if data ~= nil then
        print(data)
        if data == 'restart' then
            node.restart()
        elseif data == 'ping' then
            pcall(mqtt_publish)
        elseif data == 'update' then
            pcall(update)
        end
    end
end)

mq:on("overflow", function(client, topic, data)
    log(topic .. " partial overflowed message: " .. data )
end)

function srv_message(conn)
    conn:on("receive", function(sck, data)
        data = string.gsub(data, "%c","")
        local port, ip = sck:getpeer()
        log("srv received from "..ip..": "..data)
        if data == "status" then
            update_sensor()
            sck:send(sjson.encode(sensor))
        elseif data == "ping" then
            log("responding to srv ping")
            sck:send("triggering mqtt_publish\n")
            pcall(mqtt_publish)
        elseif data == "restart" then
            sck:send("restarting in a few seconds\n")
            local t=tmr.create()
            t:register(2000, tmr.ALARM_SINGLE, node.restart)
            t:start()
        elseif data == "update" then
            sck:send("starting update in a few seconds\n")
            local t=tmr.create()
            t:register(2000, tmr.ALARM_SINGLE, update)
            t:start()
        else
            sck:send("thanks for "..data.."\n")
        end
    end) 
    
    conn:on("sent", function() 
        conn:close() 
        print("closed connection")
        conn=nil
    end)

    conn:on("connection", function(conn) 
        print("new connection")
    end)

end

function init_temp()
    tsensor=require("ds18b20")
end

print("config wifi")
print("You have 5 seconds to abort")
print("Waiting...")
status=1
wifi.setmode(wifi.STATION)
tmr.alarm(0,5000,0, startup)
