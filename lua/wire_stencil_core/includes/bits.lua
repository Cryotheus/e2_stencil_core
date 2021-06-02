local fl_math_ceil = math.ceil
local fl_math_log = math.log
local fl_math_max = math.max

return function(number) return fl_math_max(fl_math_ceil(fl_math_log(number, 2)), 1) end