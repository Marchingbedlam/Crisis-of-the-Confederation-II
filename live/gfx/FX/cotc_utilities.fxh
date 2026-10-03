Includes = {
	"cw/camera.fxh"
	"cotc_camera_utils.fxh"
	"cotc_stars.fxh"
	"cotc_nebula.fxh"
}

PixelShader = {
	Code [[
		float4 COTC_ApplyBackgroundEffects(float3 MapColor, float MapAlpha, float MapVisibility, float3 WorldSpacePos, int StarLayerMult)
		{
			float3 Color = float3(0.0f, 0.0f, 0.0f);
			float  Alpha = 0.0f;

			COTC_ApplyStars(Color, Alpha, WorldSpacePos, StarLayerMult);
			COTC_BlendOver(Color, Alpha, MapColor, MapAlpha*MapVisibility);
			COTC_ApplyNebula(Color, Alpha, WorldSpacePos, MapVisibility);

			return float4(Color, Alpha);
		}
	]]
}
