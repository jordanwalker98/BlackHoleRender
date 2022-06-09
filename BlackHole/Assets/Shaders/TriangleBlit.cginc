#ifndef TRIANGLE_BLIT_INCLUDED
#define TRIANGLE_BLIT_INCLUDED

struct v2f {
	float4 pos : SV_POSITION;
	float4 uv : TEXCOORD0;
};

v2f vert_tri_blit(uint vertexID : SV_VertexID)
{
	v2f o;
	o.pos = float4(
		vertexID <= 1 ? -1.0 : 3.0,
		vertexID == 1 ? 3.0 : -1.0,
		0.0, 1.0
		);
	o.uv = float4(
		vertexID <= 1 ? 0.0 : 2.0,
		vertexID == 1 ? 2.0 : 0.0, 0, 0
		);

	#if UNITY_UV_STARTS_AT_TOP
		o.uv.y = 1.0 - o.uv.y;
	#endif
	/*			if (_ProjectionParams.x < 0.0)
				{
					o.uv.y = 1.0 - o.uv.y;
				}*/
	return o;
}

#endif