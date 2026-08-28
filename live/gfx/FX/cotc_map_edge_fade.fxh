Includes = {
	"cw/pdxterrain.fxh"
}

PixelShader = {
	Code [[
		static const float COTC_MAP_EDGE_FADE_WIDTH = 600.0f;

		float COTC_GetMapEdgeFade( float2 ColorMapCoords )
		{
			float2 MapWorldSize = vec2( 1.0f ) / WorldSpaceToTerrain0To1;
			float2 DistToEdge = min( ColorMapCoords, vec2( 1.0f ) - ColorMapCoords ) * MapWorldSize;

			float FadeX = smoothstep( 0.0f, COTC_MAP_EDGE_FADE_WIDTH, DistToEdge.x );
			float FadeY = smoothstep( 0.0f, COTC_MAP_EDGE_FADE_WIDTH, DistToEdge.y );

			return saturate( FadeX * FadeY );
		}

		float COTC_GetMapEdgeFadeByWorldSpace( float3 WorldSpacePos )
		{
			return COTC_GetMapEdgeFade( WorldSpacePos.xz * WorldSpaceToTerrain0To1 );
		}
	]]
}
