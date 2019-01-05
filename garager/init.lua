status=0
WIFI=1
MQTT=2
LATEST=3
CAN_DISTANCE=4
CAN_PUBLISH=5
CAN_TEMP=6

topic,_=string.gsub(wifi.sta.getmac(), ":","")
_ = nil
mq=mqtt.Client(topic, 120)
topic="/esp/"..topic

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
        if not bit.isset(status, MQTT) then
            mq:lwt(topic.."/available", "offline", 2)
            mqtt_connect()
        end
    end
    --dofile("temponly.lua")
end

function update()
    -- FIXME: Updater logic!
    http.get("http://192.168.1.85"..topic.."/updater.lua", nil, function(code, data)
        if (code ~= 200) then
            print("Updater HTTP request failed")
            dofile("temponly.lua")
        else
            print("Updater: "..code, data)
            fd = file.open("updater.lua", "w")
            if fd then
              -- write 'foo bar' to the end of the file
              fd:write(data)
              fd:close()
              status=bit.set(status, LATEST)
              dofile("temponly.lua")
            else
                print('could not write updater file')
                dofile("temponly.lua")
            end
        end
    end)
end

function mqtt_connect()
    startup = nil
    print("connecting to MQTT")
    if pcall(mq:connect("192.168.1.31", 1883, 0, 0, function(conn)
        print ("Connected to MQTT")
        mq:publish(topic.."/available", "online",2,0)
        conn:subscribe(topic.."/command", 0, function(client) 
            print("subscribe success") 
        end)
        status=bit.set(status, MQTT)
        update()
    end)) then
        print ("unexpected mqtt error, trying again in 5 sec")
        tmr.alarm(0,5000,0,mqtt_connect)
    end
end

mq:on("offline", function(client) 
    print ("MQTToffline")
    status=bit.clear(status, MQTT) 
    -- FIXME: try to reconnect?
    node.restart()
end)

-- on publish message receive event
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

-- on publish overflow receive event
mq:on("overflow", function(client, topic, data)
    print(topic .. " partial overflowed message: " .. data )
end)

print("You have 5 seconds to abort")
print("Waiting...")
status=1
print("config wifi")
wifi.setmode(wifi.STATION)
local cfg ={};
cfg.ssid="middletux";
cfg.pwd="HidjTdihs2013";
cfg.save=true;
wifi.sta.config(cfg)
cfg = nil
tmr.alarm(0,5000,0, startup)
