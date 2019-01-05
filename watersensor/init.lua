function startup()
    print("Connecting to WiFi access point...")
    wifi.setmode(wifi.STATION)
    local cfg ={};
    cfg.ssid="DELETED";
    cfg.pwd="DELETED";
    cfg.save=true;
    wifi.sta.config(cfg)
    -- wifi.sta.connect() not necessary because config() uses auto-connect=true by default
    tmr.alarm(1, 1000, 1, function()
        if wifi.sta.getip() == nil then
            print("Waiting for IP address...")
        else
            tmr.stop(1)
            print("WiFi connection established, IP address: " .. wifi.sta.getip())
            tmr.alarm(0, 10, 0, send_sleep)
        end
    end)
end

function startloop()
    -- start loop
    print("starting watersensor")
    gpio.mode(w,gpio.OUTPUT)
    gpio.write(w, gpio.LOW)
    gpio.mode(r, gpio.INPUT)
    gpio.mode(s, gpio.HIGH)
    tmr.alarm(0,100,tmr.ALARM_AUTO, loop)
end

function loop()
    gpio.write(w, gpio.HIGH)
    if c < 5 then
        water=water+gpio.read(r)
        c=c+1
    else
        tmr.stop(0)
        gpio.write(w, gpio.LOW)
        if water<2 then
             if old_water==0 then 
                --gpio.write(s, gpio.LOW)
                state_changed=1
                print("WATER!") 
                old_water=1
                file.open("water","w")
                file.close()
                tmr.alarm(2, 10, 0, startup)
             end
        else
             --gpio.write(s, gpio.HIGH)
             if old_water==1 then 
                state_changed=1
                print("all good") 
                old_water=0
                file.remove("water")
                tmr.alarm(2, 10, 0, startup)
             end
        end
        tmr.alarm(0, 10, 0, go_sleep)
    end
end

function send_sleep()
    url="http://maker.ifttt.com/trigger/water/with/key/ggSTpwpOoD5Pg9BrdhiqzJXVETZ5hg5kA-3LuW5oQmE?value1="
    if water<2 then
        url=url.."ON"
    else
        url=url.."OFF"
    end
    http.get(url, nil, function (code, data) 
        print(code)
        node.dsleep(dsleep)
    end)
end

function go_sleep()
    -- if state hasn't changed, go sleep, otherwise do nothing. send_sleep is in charge
    if state_changed==0 then
        node.dsleep(dsleep) 
    end
    --gpio.mode(5,gpio.OUTPUT)
    --gpio.write(5,gpio.HIGH)
end

adc.force_init_mode(adc.INIT_VDD33)
-- turn on LED so we know when it's running
gpio.write(3, gpio.LOW)
water=0
-- set old_water from persistent storage in file system, so we know how last run ended
if file.exists("water") then
    old_water=1
else
    old_water=0
end
state_changed=0
c=0
-- we write to pin 4
w=4
-- we read from pin 0
r=6
-- we signal on internal LED on pin 3
s=3
-- sleep between each read
dsleep = 15 * 1000000


a,b = node.bootreason()
print("bootreason: ",a,",",b)
if a==2 and b== 5 then
    tmr.alarm(0,1000,0, startloop)
else
    print("You have 5 seconds to abort")
    print("Waiting...")
    tmr.alarm(0, 5000, 0, startloop)
end

