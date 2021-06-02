if CLIENT then
	return {
		clear = render.ClearStencil,
		clear_obedient = function(color) render.ClearBuffersObeyStencil(color.r, color.g, color.b, color.a, false) end,
		draw_quad = function(color, stencil)
			--todo: decode color
			cam.Start2D()
			surface.SetDrawColor(color)
			surface.DrawRect(0, 0, ScrW(), ScrH())
			cam.End2D()
		end,
		
		draw_entities = function(layer, stencil)
			local entities = stencil.entities[layer]
			
			if entities then
				for entity in pairs(entities) do
					--more?
					if IsValid(entity) then entity:DrawModel() end
				end
			end
		end,
		
		--perform_operation = render.PerformFullScreenStencilOperation, --we need to first understand if this takes any parameters
		
		set_compare = render.SetStencilCompareFunction,
		set_fail_operation = render.SetStencilFailOperation,
		set_pass_operation = render.SetStencilPassOperation,
		set_reference_value = render.SetStencilReferenceValue,
		set_test_mask = render.SetStencilTestMask,
		set_write_mask = render.SetStencilWriteMask,
		set_zfail_operation = render.SetStencilZFailOperation
	}
else
	return {
		"clear",
		"clear_obedient",
		"draw_quad",
		"draw_entities",
		--"perform_operation",
		"set_compare",
		"set_fail_operation",
		"set_pass_operation",
		"set_reference_value",
		"set_test_mask",
		"set_write_mask",
		"set_zfail_operation"
	}
end