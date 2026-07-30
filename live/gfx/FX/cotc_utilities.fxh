Includes = {
	"cw/camera.fxh"
	"cotc_stars.fxh"
}

PixelShader = {
	Code [[
		float COTC_GetHeightBasedAlpha()
		{
			return smoothstep( 70.0f, 90.0f, CameraPosition.y );
		}

		void COTC_ApplyBackgroundEffects(inout float3 Color, inout float Alpha, float3 WorldSpacePos, int StarLayerMult)
		{
			COTC_ApplyStars(Color, Alpha, WorldSpacePos, StarLayerMult);
		}
	]]
}
