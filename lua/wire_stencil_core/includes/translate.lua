--this file returns the translate function used in this addon
return function(key, phrases)
	local text
	
	if phrases then text = language.GetPhrase(key)
	elseif istable(key) then
		text = language.GetPhrase(key.key)
		phrases.text = nil
	else return language.GetPhrase(key) end
	
	return string.gsub(text, "%[%:(.-)%]", phrases)
end