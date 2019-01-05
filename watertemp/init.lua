function startup()
    if file.open("init.lua") == nil then
        print("init.lua deleted or renamed")
    else
        print("Running")
        file.close("init.lua")
        -- the actual application is stored in 'application.lua'
        dofile("watertemp.lua")
    end
end

adc.force_init_mode(adc.INIT_VDD33)

a,b = node.bootreason()
print("bootreason: ",a,",",b)
if a==2 and b== 5 then
    tmr.alarm(0,10,0, startup)
else
    print("You have 5 seconds to abort")
    print("Waiting...")
    tmr.alarm(0, 5000, 0, startup)
end
