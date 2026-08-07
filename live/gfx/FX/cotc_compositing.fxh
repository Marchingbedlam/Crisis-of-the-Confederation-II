PixelShader = {
	Code [[
		// Composites a source colour OVER a destination that is itself only PARTLY opaque
		void COTC_BlendOver( inout float3 DstColor, inout float DstAlpha, in float3 SrcColor, in float SrcAlpha )
		{
			const float OutAlpha = SrcAlpha + DstAlpha * ( 1.0f - SrcAlpha );
			const float ColorWeight = OutAlpha > 1e-5f ? SrcAlpha / OutAlpha : 0.0f;

			DstColor = lerp( DstColor, SrcColor, ColorWeight );
			DstAlpha = OutAlpha;
		}
	]]
}
