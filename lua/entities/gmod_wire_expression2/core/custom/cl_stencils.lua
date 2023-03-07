--locals
local descriptions = E2Helper.Descriptions

--LOCALIZE: E2 helper descriptions!
descriptions["stencilAddEntity(nne)"] = "Adds an entity to the stencil's specified layer; the first layer is 1. most stencils have 2 layers and show their effects when the two overlap."
descriptions["stencilAddEntity(nnn)"] = "Adds an hologram to the stencil's specified layer; the first layer is 1. most stencils have 2 layers and show their effects when the two overlap."
descriptions["stencilCompile(n)"] = "On the next tick, the stencil is sent to clients which will compile the stencil's instructions for rendering. This is required for custom stencils. Don't call this, as it's used for custom stencils which are not yet implemented."
--descriptions["stencilCreate(n)"] = "Creates a stencil with the given index and without any instructions. The stencil will not be usable until stencilCompile is called."
descriptions["stencilCreate(nn)"] = "Creates a stencil with the given index and prefab. Automatically calls stencilCompile."
descriptions["stencilDelete(n)"] = "Deletes the stencil."
descriptions["stencilEnable(nn)"] = "If enable is set to 0, stops networking the stencil and removes if from all clients. Setting this to 1 will do the opposite."
descriptions["stencilHook(nn)"] = "Sets the stencil's render hook given a STENCILHOOK constant. Must be done before the stencil is compiled."
descriptions["stencilInstructionCount"] = "Returns the number of instructions a stencil has. Returns 0 for prefabricated stencils."
descriptions["stencilPrefabLayerCount"] = "Returns the number of entity layers in the stencil. Prefabricated stencils always have their layers in a sequence starting from 1, thus it is safe to assume 1 - <this function's return> is all the available entity layers."
descriptions["stencilPurge"] = "Deletes all of the chip's stencils."
descriptions["stencilRemoveEntity(ne)"] = "Removes the entity from all of the stencil's layers."
descriptions["stencilRemoveEntity(nn)"] = "Removes the hologram from all of the stencil's layers."
descriptions["stencilRemoveEntity(nne)"] = "Removes the entity from the stencil's specified layer."
descriptions["stencilRemoveEntity(nnn)"] = "Removes the hologram from the stencil's specified layer."
--descriptions["stencilSetInstructions(nr)"] = "Sets the stencil's instructions. This must be done before stencilCompile." --POST: custom stencils!
--descriptions["stencilParameter(n...)"] = "Sets the stencil's parameters. This is not available on most prefabs."
--descriptions["stencilParameter(nn...)"] = "Sets the stencil's parameter starting from the given index. This is not available on most prefabs."
--descriptions["stencilVisible(nen)"] = "Sets the stencil's visibility for the specified player. 0 will hide it, anything else will show it." --POST: visibility!
--descriptions["stencilVisible(nn)"] = "Sets the stencil's visibility. 0 will hide it, anything else will show it."
--descriptions["stencilVisible(nrn)"] = "Sets the stencil's visibility for all players in the array. 0 will hide it, anything else will show it."