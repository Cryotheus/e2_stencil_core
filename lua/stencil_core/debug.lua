function _PrintTable( t, indent, done )
	local Msg = Msg

	done = done or {}
	indent = indent or 0
	local keys = table.GetKeys( t )

	table.sort( keys, function( a, b )
		if ( isnumber( a ) && isnumber( b ) ) then return a < b end
		return tostring( a ) < tostring( b )
	end )

	done[ t ] = true

	for i = 1, #keys do
		local key = keys[ i ]
		local value = t[ key ]
		Msg( string.rep( "\t", indent ) )

		if  ( istable( value ) && !done[ value ] ) then

			done[ value ] = true
			Msg( key, ":\n" )
			_PrintTable ( value, indent + 2, done )
			done[ value ] = nil

		else

			Msg( key, "\t=\t", value, "\n" )

		end

	end

end