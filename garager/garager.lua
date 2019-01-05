print('executing temponly.lua')

sda = 6 -- SDA Pin
scl = 7 -- SCL Pin
ds=2
trig=0
echo=5
signal=4
button=8

door_treshold=40


temp=0
start=0
done=0
state=0
prior=10000
door_open=0
door=""
dist=0
tsensor=nil

problems=0


function init_display(sda,scl) --Set up the u8glib lib
     local sla = 0x3C
     i2c.setup(0, sda, scl, i2c.SLOW)
--     disp = u8g2.ssd1306_i2c_128x64_noname(0,sla)
     disp = u8g2.ssd1306_i2c_128x32_univision(0,sla)
     disp:setFont(u8g2.font_unifont_t_symbols)
--     disp:setFont(u8g2.font_6x10_tf)
     disp:setFontRefHeightExtendedText()
--     disp:setDefaultForegroundColor()
     disp:setFontPosTop()
end

function updateDisp(text)
    --print("updating display")
    disp:clearBuffer()
    disp:setFont(u8g2.font_6x10_tf)
    disp:drawStr(5,1,"Status: "..status)
    disp:setFont(u8g2.font_unifont_t_symbols)
--    disp:drawStr(5,15, "Temp: "..temp)
    disp:drawStr(5,10,"Door: "..door)
    disp:setFont(u8g2.font_6x10_tf)
    disp:drawStr(5,22,"Temp: "..temp)
    disp:sendBuffer()
end

function readTemp2()
    tsensor:read_temp(readout, ds)
    --print(temp)
    updateDisp("")
end

function readout(te)
  for addr, tem in pairs(te) do
    --print(string.format("Sensor %s: %s °C", ('%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X'):format(addr:byte(1,8)), tem))
    if not tem==0 then
        temp=tem
        -- FIXME: after n failed attempts, unset CAN_TEMP
    end
  end
end

function echo_cb(level, when)
     --print("callback", level)
     if level == 1 then
          --print("callback up", level, when)
          start=when
          gpio.trig(echo, "down")
     else
          done=when
          --print("callback down", level, when)
     end
end

function measure_distance()
     --print("trying to measure distance")
     gpio.trig(echo, "both", echo_cb)
     gpio.write(trig, gpio.HIGH)
     tmr.delay(100)
     gpio.write(trig, gpio.LOW)
     tmr.alarm(1,200, tmr.ALARM_SINGLE, distance)  
end

function distance()
   dist = (done-start) / 58
   done=start
   --print(dist)

   if dist > 0 then 
     --print("distance:", distance) 
     status=bit.set(status, CAN_DISTANCE)
     tmr.alarm(2,180000,1,mqtt_publish)
     if dist < door_treshold then
          -- door open!
          if door_open == 0 then 
            tmr.alarm(1,20,0,report_change)
          end
          door_open=1
     else
          if door_open == 1 or prior > 100 then 
            tmr.alarm(1,20,0,report_change)
          end
          door_open=0
     end     
   else
       status=bit.clear(status, CAN_DISTANCE)
       tmr.stop(2)
   end
   prior=0
end

function report_change()
    if door_open == 1 then 
        print("door open!")
        door="OPEN"
        -- notify state change?
        gpio.write(signal, gpio.LOW)
        updateDisp()
    else
        print("door closed!")
        door="CLOSED"
        -- notify state change?
        gpio.write(signal, gpio.HIGH)
        updateDisp()
       -- tmr.alarm(5,300, tmr.ALARM_SINGLE, measure)
    end
    mqtt_publish()
end

function button_press()
      gpio.write(button,1)
      tmr.alarm(6,1500,0, button_release)
end

function button_release()
      gpio.write(button,0)
end

function loop()
    measure_distance()
    --readMotion()
    tmr.alarm(4,100,0,updateDisp)
end

function mqtt_publish()
    local msg = '{"status":"'..status..'","door":"'..door_open..'","temp":"'..temp..'","problems":"'..problems..'"}'
    local ret = mq:publish(topic.."/status", msg,1,0, function(client)
        print("data sent via mqtt")
    end)
    if ret == true then
        status = bit.set(status, CAN_PUBLISH)
    else
        status = bit.clear(status, CAN_PUBLISH)
        problems = problems + 1
        if problems==10 then 
            node.restart()
        end
    end
end

function init_temp()
    tsensor=require("ds18b20")
end
--ds18b20.setup(ds)

if pcall(init_temp) then
    print("loaded ds18b20 module")
    status=bit.set(status, CAN_TEMP)
end
gpio.mode(signal, gpio.OUTPUT)
--gpio.mode(button, gpio.OUTPUT)
--gpio.write(signal, gpio.LOW)
--gpio.write(button, gpio.LOW)
gpio.mode(trig,gpio.OUTPUT)
gpio.mode(echo,gpio.INT)
--gpio.mode(motion_pin, gpio.INPUT)
-- turn off builtin LED
--gpio.write(4,gpio.HIGH)

init_display(sda,scl)

if bit.isset(status, CAN_TEMP) then
    tmr.alarm(3,3031,1,readTemp2)
end
tmr.alarm(5,2052,1,loop)

