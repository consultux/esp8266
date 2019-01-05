-- init mqtt client with keepalive timer 120sec
m = mqtt.Client("huzzah2", 10, '', '')
val = 0
dsleep = 3600 * 1000000
progress = 0
counter = 0

-- deep sleep after 10 seconds no matter what
tmr.alarm(6,30000, tmr.ALARM_SINGLE, function(timer) 
    print("emergency brake - going to sleep")
    go_sleep()
end)

-- check if WiFi is connected, otherwise go to sleep

function go_sleep()
    node.dsleep(dsleep) 
    --gpio.mode(5,gpio.OUTPUT)
    --gpio.write(5,gpio.HIGH)
end


function measure()
    print("trying to measure")
    ds18b20.setup(6)
    ds18b20.read(
    function(ind,rom,res,temp,tdec,par)
        --print(ind,string.format("%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",string.match(rom,"(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")),res,temp,tdec,par)
        val = temp
        print("measured ",val)
        --loop()
    end,{"28:FF:59:51:C0:17:01:F6"})
    return val
end

--tmr.alarm(2,1000,1,measure)

-- setup Last Will and Testament (optional)
-- Broker will publish a message with qos = 0, retain = 0, data = "offline" 
-- to topic "/lwt" if client don't send keepalive packet
--m:lwt("/lwt", "huzzah2 went offline", 0, 0)
--[[
m:on("connect", function(client) 
    print("connected") 
    m:publish("/huzzah2/ip", wifi.sta.getip(),1,0, function(client) print("sent") end)
    c = 1   
end)
m:on("offline", function(client) print ("on offline") end)
--]]

function loop()
    measure()
    counter = counter + 1
    if progress == 0 then
        -- fresh start, check wifi first
        if wifi.sta.status() == wifi.STA_GOTIP then
            progress = 1
            print("wifi connected ", counter)
        end
    elseif progress == 1 then
        -- read value from sensor
        if val == 0 then measure() end
        if val ~= 0 or counter > 6 then
            progress = 2
            print("water temp is ", val, " ", counter)
        end
    elseif progress == 2 then
        -- connect to mqtt
        if pcall(m:connect("192.168.1.31", 1883, 0, 0, function(conn)
            print ("Connected to MQTT ", counter)
            local msg = '{"battery":"'..(adc.readvdd33())..'","counter":"'..counter..'", "wtemp":"'..val..'"'
            if val ~= 0 then
                msg = msg..', "warn":""}'
            else
                msg = msg..', "warn":"sensor error"}'
            end
            m:publish("/huzzah2/status", msg,1,0, function(client)
                print("data sent via mqtt")
                progress = 3
            end)
        end)) then
            print ("unexpected mqtt error")
            progress = 3
        end
    elseif progress == 3 then
        print("going to sleep now")
        go_sleep()
    else
        print("we should never see this ", counter)
    end

end

tmr.alarm(0,1000,tmr.ALARM_AUTO, function() loop() end)
