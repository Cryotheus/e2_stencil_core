E2Lib.RegisterExtension("stencils", true, "Allows E2 to create and manipulate intangible stencils. Stencils can be used to control rendering with specified entities.")

--local functions

--e2functions
__e2setcost(3)
e2function void stencilCreate(number index)
	
end

--net
net.Receive("e2_stencil_core_init", function(length, ply)
	--sync player
	print("shut up oneil", length, ply)
end)