print('executing garager.lua')

SDA = 6 -- SDA Pin
SCL = 7 -- SCL Pin
DS=2
TRIG=0
ECHO=5
SIGNAL=4
BUTTON=8

--FIXME3: read from config
DOOR_TRESHOLD=40

sensor.temp=0
sensor.door=-1
dist=0
door_status=0

start=0
done=0

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
    local dstr=""
    if sensor.door==1 then
        dstr = "OPEN"
    elseif sensor.door==0 then
        dstr = "CLOSED"
    else
        dstr = "UNKNOWN"
    end
    disp:drawStr(5,10,"Door: "..dstr)
    disp:setFont(u8g2.font_6x10_tf)
    disp:drawStr(5,22,"Temp: "..sensor.temp)
    disp:sendBuffer()
end

function readTemp2()
    tsensor:read_temp(readout, DS)
    --print(temp)
end

function readout(temp)
  local emtpy=true
  for addr, tem in pairs(tsensor.temp) do
    --print(string.format("Sensor %s: %s °C", ('%02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X'):format(addr:byte(1,8)), tem))
    if tem ~= "0.0" then
        sensor.temp=tem
        status=bit.set(status, CAN_TEMP)
        empty=false
        updateDisp("")
    else
        print("read 0.0 temperature")
    end
    if empty == true then
        print("can't read temp sensor")
        status=bit.clear(status, CAN_TEMP)
    end
  end
end

function echo_cb(level, when)
     --print("callback", level)
    if level == 1 then
        --print("callback up", level, when)
        start=when
        gpio.trig(ECHO, "down")
    else
        --print("callback down", level, when)
        dist = (when-start) / 58
    end
end

function measure_distance()
     --print("trying to measure distance")
     gpio.trig(ECHO, "both", echo_cb)
     gpio.write(TRIG, gpio.HIGH)
     tmr.delay(100)
     gpio.write(TRIG, gpio.LOW)
     tmr.alarm(1,200, tmr.ALARM_SINGLE, distance)  
end

function distance()
    local reading
    if dist <= 0 then 
        reading = -1
        status=bit.clear(status, CAN_DISTANCE)
    elseif dist < DOOR_TRESHOLD then
        reading = 1
        status=bit.set(status, CAN_DISTANCE)
    else
        reading =0
        status=bit.set(status, CAN_DISTANCE)
    end
    if door_status > 0 then
        -- this is a second read after a change in status
        --print("read distance after change in status, now "..reading)
        door_status = bit.set(door_status, reading + 4)
        if (door_status % 9) == 0 then
            --print("change in status detected, now "..reading)
            sensor.door = reading
            tmr.alarm(1,20,0,report_change)
        end
        door_status = 0
    elseif reading ~= sensor.door then
        -- this is a first discovery of a status change
        door_status = bit.set(door_status, reading + 1)
        --print("possible status change detected, reading again to be sure "..reading)
    end
end

function report_change()
    pcall(mqtt_publish)
    if sensor.door == 1 then 
        print("door open!")
        --FIXME3: move setting text of door into updateDisp(), eliminate global variable?
        gpio.write(SIGNAL, gpio.LOW)
    else
        print("door closed!")
        gpio.write(SIGNAL, gpio.HIGH)
    end
    updateDisp()
end

function button_press()
      gpio.write(BUTTON,1)
      tmr.alarm(6,1500,0, button_release)
end

function button_release()
      gpio.write(BUTTON,0)
end

function mqtt_publish()
    update_sensor()
    local msg = sjson.encode(sensor)
    if mq:publish(topic.."/status", msg,1,0) then
        print("data sent via mqtt")
        status = bit.set(status, CAN_PUBLISH)
        tmr.softwd(WD_ALLGOOD)
    else
        status = bit.clear(status, CAN_PUBLISH)
        -- disabled. could add time to running wd from mqtt:offline
        --tmr.softwd(WATCHDOG)
        log("mqtt_publish failed")
    end
end


gpio.mode(SIGNAL, gpio.OUTPUT)
--gpio.mode(BUTTON, gpio.OUTPUT)
--gpio.write(SIGNAL, gpio.LOW)
--gpio.write(BUTTON, gpio.LOW)
gpio.mode(TRIG,gpio.OUTPUT)
gpio.mode(ECHO,gpio.INT)

init_display(SDA,SCL)
init_display=nil

if bit.isset(status, CAN_TEMP) then
    readTemp2()
    tmr.alarm(3,5031,1,readTemp2)
end
tmr.alarm(5,2052,1,measure_distance)
tmr.alarm(2,300000,1,mqtt_publish)
 
