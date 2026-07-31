Includes = {
	"cw/camera.fxh"
	"cotc_stars.fxh"
}

PixelShader = {
	Code [[
		float COTC_GetHeightBasedAlpha()
		{
			return smoothstep( 50.0f, 60.0f, CameraPosition.y );
		}

		void COTC_ApplyBackgroundEffects(inout float3 Color, inout float Alpha, float3 WorldSpacePos, int StarLayerMult)
		{
			COTC_ApplyStars(Color, Alpha, WorldSpacePos, StarLayerMult);
		}
	]]
}
