//
//  shader.metal
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//

#include <metal_stdlib>
using namespace metal;

// MARK: Const
#define MAX_T 10000000.

#define RED        float3(1.0, 0.0, 0.0)
#define GREEN      float3(0.0, 1.0, 0.0)
#define BLUE       float3(0.0, 0.0, 1.0)
#define YELLOW     float3(1.0, 1.0, 0.0)
#define CYAN       float3(0.0, 1.0, 1.0)
#define MAGENTA    float3(1.0, 0.0, 1.0)
#define ORANGE     float3(1.0, 0.5, 0.0)
#define PURPLE     float3(0.5, 0.0, 0.5)
#define PINK       float3(1.0, 0.75, 0.8)
#define BROWN      float3(0.6, 0.3, 0.0)

#define WHITE      float3(1.0, 1.0, 1.0)
#define GRAY       float3(0.5, 0.5, 0.5)
#define DARK_GRAY  float3(0.25, 0.25, 0.25)
#define BLACK      float3(0.0, 0.0, 0.0)

#define LIGHT_GRAY float3(0.8, 0.8, 0.8)
#define GOLD       float3(1.0, 0.84, 0.0)
#define TURQUOISE  float3(0.25, 0.88, 0.82)

#define EPS        1e-4

//MARK: Vertex
struct VertexOut {
	float4 position [[position]];
	float2 uv;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
	float2 positions[6] = {
		float2(-1.0, -1.0),
		float2( 1.0, -1.0),
		float2(-1.0,  1.0),
		float2(-1.0,  1.0),
		float2( 1.0, -1.0),
		float2( 1.0,  1.0),
	};
	
	VertexOut out;
	out.position = float4(positions[vertexID], 0, 1);
	out.uv = (positions[vertexID] + 1.0) * 0.5;
	return out;
}


//MARK: Struct
struct Material {
	float3 color;
	float3 emitingColor;
	float emitingStrength;
	float smoothness;
};


struct Sphere {
	float3 center;
	float radius;
	Material material;
};

struct Triangle {
	float3 A;
	float3 B;
	float3 C;
	float3 n;
	Material material;
};

struct Ray {
	float3 origin;
	float3 dir;
};

struct RayHit {
	bool hit;
	float t;
	float3 n;
	Material material;
};


//MARK: Constructors
Material createMaterial(float3 color, float3 emitingColor, float emitingStrength, float smoothness) {
	Material m;
	m.color = color;
	m.emitingColor = emitingColor;
	m.emitingStrength = emitingStrength;
	m.smoothness = smoothness;
	
	return m;
}

Material createMaterial(float3 color, float3 emitingColor, float emitingStrength) {
	Material m;
	m.color = color;
	m.emitingColor = emitingColor;
	m.emitingStrength = emitingStrength;
	m.smoothness = 0.;
	
	return m;
}
#define WHITE_MAT  createMaterial(float3(1.), float3(0.), 0.)


Sphere createSphere(float3 center, float radius, Material material) {
	Sphere s;
	s.center = center;
	s.radius = radius;
	s.material = material;
	
	return s;
}

Triangle createTriangle(float3 A, float3 B, float3 C, float3 n, Material material) {
	Triangle t;
	t.A = A;
	t.B = B;
	t.C = C;
	t.n = n;
	t.material = material;
	
	return t;
}

Triangle createTriangle(float3 A, float3 B, float3 C, Material material) {
	return createTriangle(A, B, C, cross(C - A, B - A), material);
}

Triangle createTriangle(float3 A, float3 B, float3 C, float3 color) {
	return createTriangle(A, B, C, cross(C - A, B - A), createMaterial(color, BLACK, 0.));
}

Sphere createSphere(float3 center, float radius, float3 color) {
	return createSphere(center, radius, createMaterial(color, BLACK, 0.));
}

Ray createRay(float3 origin, float3 dir) {
	Ray r;
	r.origin = origin;
	r.dir = dir;
	
	return r;
}
#define BLANK_RAY  RayHit(false, MAX_T, float3(0.), WHITE_MAT)



//MARK: Random
uint wang_hash(uint seed) {
	seed = (seed ^ 61) ^ (seed >> 16);
	seed *= 9;
	seed = seed ^ (seed >> 4);
	seed *= 0x27d4eb2d;
	seed = seed ^ (seed >> 15);
	return seed;
}

float RandomFloat01(thread uint &state) {
	state = wang_hash(state);
	return float(state) / 4294967296.0;
}

float RandomValueNormalDistribution(thread uint &state) {
	float theta = 2.0 * 3.1415926 * RandomFloat01(state);
	float rho = sqrt(-2.0 * log(RandomFloat01(state)));
	return rho * cos(theta);
}

float3 RandomDirection(thread uint &state) {
	float x = RandomValueNormalDistribution(state);
	float y = RandomValueNormalDistribution(state);
	float z = RandomValueNormalDistribution(state);
	return normalize(float3(x, y, z));
}

float3 RandomCosineDirection(float3 normal, thread uint &state) {
	float u1 = RandomFloat01(state);
	float u2 = RandomFloat01(state);
	
	float r = sqrt(u1);
	float theta = 2.0 * 3.1415926 * u2;
	
	float x = r * cos(theta);
	float y = r * sin(theta);
	float z = sqrt(1.0 - u1);
	
	// On doit aligner cette direction avec la normale
	float3 up = fabs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 tangent = normalize(cross(up, normal));
	float3 bitangent = cross(normal, tangent);
	
	return normalize(x * tangent + y * bitangent + z * normal);
}

//MARK: Intersect
float intersectSphere(float3 center, float radius, float3 origin, float3 dir) {
	float3 oc = origin - center;
	float a = dot(dir, dir);
	float b = 2.0 * dot(oc, dir);
	float c = dot(oc, oc) - radius * radius;
	float discriminant = b * b - 4.0 * a * c;
	
	if (discriminant < 0.0) return -1.0;
	float t1 = (-b - sqrt(discriminant)) / (2.0 * a);
	float t2 = (-b + sqrt(discriminant)) / (2.0 * a);
	if (t1 > 0.0) return t1;
	if (t2 > 0.0) return t2;
	return -1.0;
}

float intersectSphere(Sphere sphere, Ray ray) {
	return intersectSphere(sphere.center, sphere.radius, ray.origin, ray.dir);
}


float intersectTriangle(float3 A, float3 B, float3 C, float3 n, float3 origin, float3 dir)
{
	float3 AB = B - A;
	float3 AC = C - A;
	
	//if (dot(n, dir) > 0) return -1.;
	
	// Calcul du déterminant
	float3 pvec = cross(dir, AC);
	float det   = dot(AB, pvec);
	
	// Rayon parallèle ou triangle dos tourné (selon que l’on veut culler ou pas)
	if (fabs(det) < 0)
		return -1.0;
	
	float invDet = 1.0 / det;
	
	// u (≃ alpha)
	float3 tvec = origin - A;
	float u = dot(tvec, pvec) * invDet;
	if (u < 0.0 || u > 1.0)
		return -1.0;
	
	// v (≃ beta)
	float3 qvec = cross(tvec, AB);
	float v = dot(dir, qvec) * invDet;
	if (v < 0.0 || (u + v) > 1.0)
		return -1.0;
	
	// t
	float t = dot(AC, qvec) * invDet;
	return (t > EPS) ? t : -1.0;
}



float intersectTriangle(Triangle triangle, Ray ray) {
	return intersectTriangle(triangle.A, triangle.B, triangle.C, triangle.n, ray.origin, ray.dir);
}

//MARK: Ray
struct RayHit RayHit(bool hit, float t, float3 n, Material material) {
	struct RayHit r;
	r.hit = hit;
	r.t = t;
	r.n = n;
	r.material = material;
	
	return r;
}

float3 rayAt(float3 origin, float3 dir, float t) {
	return origin + t * dir;
}

struct RayHit rayCollisionSpheres(float3 origin, float3 dir, constant Sphere* spheres, int nb) {
	float t = MAX_T;
	Sphere sphere;
	float _t;
	for (int i = 0; i < nb; i++) {
		_t = intersectSphere(spheres[i].center, spheres[i].radius, origin, dir);
		
		if (_t > 0 && _t < t) {
			sphere = spheres[i];
			t = _t;
		}
	}
	
	return RayHit(t != MAX_T, t, rayAt(origin, dir, t) - sphere.center, sphere.material);
}

struct RayHit rayCollisionSpheres(Ray ray, constant Sphere* spheres, int nb) {
	return rayCollisionSpheres(ray.origin, ray.dir, spheres, nb);
}

struct RayHit rayCollisionTriangles(float3 origin, float3 dir, constant Triangle* triangles, int nb) {
	float t = MAX_T;
	Triangle triangle;
	float _t;
	for (int i = 0; i < nb; i++) {
		_t = intersectTriangle(triangles[i], createRay(origin, dir));
		
		if (_t > 0. && _t < t) {
			triangle = triangles[i];
			t = _t;
		}
	}
	
	return RayHit(t != MAX_T, t, triangle.n, triangle.material);
}

struct RayHit rayCollisionTriangles(Ray ray, constant Triangle* triangles, int nb) {
	return rayCollisionTriangles(ray.origin, ray.dir, triangles, nb);
}

struct RayHit rayCollosionAll(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles) {
	struct RayHit rayHitB = rayCollisionSpheres(ray, spheres, nbSpheres);
	struct RayHit rayHitT = rayCollisionTriangles(ray, triangles, nbTriangles);
	
	if (!(rayHitB.hit || rayHitT.hit)) return BLANK_RAY; //Aucune collisions
	
	struct RayHit rayH;
	rayH.hit = true;
	if (rayHitB.hit) { //On touche une sphère
		if (rayHitT.hit && rayHitT.t < rayHitB.t) { //Un triangle est devant
			rayH.t = rayHitT.t;
			rayH.n = rayHitT.n;
			rayH.material = rayHitT.material;
		} else { // Pas de triangle, ou derrière
			rayH.t = rayHitB.t;
			rayH.n = rayHitB.n;
			rayH.material = rayHitB.material;
		}
	} else {
		rayH.t = rayHitT.t;
		rayH.n = rayHitT.n;
		rayH.material = rayHitT.material;
	}
	
	return rayH;
}

float3 lerp(float3 a, float3 b, float p) {
	return p * a + (1 - p) * b;
}

//MARK: Color
float3 getColor(float3 origin, float3 dir, Sphere spheres[], int nb) {
	float t = MAX_T;
	float3 color = float3(0.);
	
	float _t;
	for (int i = 0; i < nb; i++) {
		_t = intersectSphere(spheres[i].center, spheres[i].radius, origin, dir);
		
		if (_t > 0 && _t < t) {
			t = _t;
			color = spheres[i].material.color;
		}
	}
	
	return color;
}



float3 getColor(float3 origin, float3 dir, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, int maxDepth, int minDepth, thread uint &rngState) {
	float3 incomingLight = float3(0.);
	float3 color = float3(1.);
	Ray newRay = createRay(origin, dir);
	
	
	for (int i = 0; i < maxDepth; i++) {
		struct RayHit rayHit = rayCollosionAll(newRay, spheres, nbSpheres, triangles, nbTriangles);
		
		if (!rayHit.hit) {
//			float3 backgroundColor = float3(0.1, 0.1, 0.15);
//			incomingLight += backgroundColor * color;
			break;
		}

		
		Material material = rayHit.material;
		
		newRay.origin = rayAt(newRay.origin, newRay.dir, rayHit.t);

		float3 specularDir = reflect(newRay.dir, rayHit.n);
		float3 diffuseDir  = normalize(rayHit.n + RandomDirection(rngState));
		
		float3 emitedLight = material.emitingColor * material.emitingStrength;
		incomingLight += emitedLight * color;
		color *= material.color;
		
		if (material.smoothness > 1 - 1e-3) {
			newRay.dir = specularDir;
		} else if (material.smoothness <  1e-3) {
//			if (i >= minDepth) {
//				break;
//			}
			newRay.dir = diffuseDir;
		} else {
			newRay.dir = normalize(mix(specularDir, diffuseDir, material.smoothness));
		}
		
		
	}
	
	return incomingLight;
}

float3 getRayDir(float x, float y, float3 topLeft, float3 vx, float3 vy, float3 cameraPos) {
	float3 pointOnViewport = topLeft + x * vx + y * vy;
	
	return normalize(pointOnViewport - cameraPos);
}

//MARK: Main
//fragment float4 fragment_main(VertexOut in [[stage_in]],
//							  constant float2 &resolution [[buffer(0)]],
//							  constant float3 &cameraPos [[buffer(1)]],
//							  constant Sphere* spheres [[buffer(2)]],
//							  constant int &nbSpheres [[buffer(3)]],
//							  constant Triangle* triangles [[buffer(4)]],
//							  constant int &nbTriangles [[buffer(5)]],
//							  constant uint& frameCount [[buffer(6)]],
//							  constant bool& isAccumulating [[buffer(7)]],
//							  texture2d<float, access::read_write> accumulationTexture [[texture(0)]],
//							  constant float3 &topLeft [[buffer(8)]],
//							  constant float3 &vx [[buffer(9)]],
//							  constant float3 &vy [[buffer(10)]])
//{
//
//	thread uint rngState = uint(uint(in.position.x) * uint(1973) + uint(in.position.y) * uint(9277) + uint(frameCount) * uint(26699)) | uint(1);
//	
////	float2 uv = in.uv * 2.0 - 1.0;
////	uv.x *= resolution.x / resolution.y;
////	
//	float3 rayOrigin = cameraPos;
//	
//	float2 pixel = in.uv * resolution;
//	float3 pixelPos = topLeft + pixel.x * vx + pixel.y * vy;
//	float3 rayDir = normalize(pixelPos - cameraPos);
//
//	
//	float3 color = getColor(rayOrigin, rayDir, spheres, nbSpheres, triangles, nbTriangles, 5, 3, rngState);
//	
//	// Accumulation 
//	if (isAccumulating) {
//		int NumRaysPerPixel = 10;
//		
//		float3 totalIncomingLight = float3(0.);
//		for (int rayIndex = 0; rayIndex < NumRaysPerPixel; rayIndex ++) {
//			float dx = RandomFloat01(rngState);
//			float dy = RandomFloat01(rngState);
//			
//			float2 pixelSample = pixel + float2(dx, dy);
//			rayDir = getRayDir(pixelSample.x, pixelSample.y, topLeft, vx, vy, rayOrigin);
//			
//			totalIncomingLight += getColor(rayOrigin, rayDir, spheres, nbSpheres, triangles, nbTriangles, 20, 20, rngState);
//		}
//		color = (totalIncomingLight + color) / (NumRaysPerPixel + 1);
//		
//		float4 accumulatedColor = accumulationTexture.read(uint2(in.position.x, in.position.y));
//		float newSampleCount = accumulatedColor.a + 1.0;
//		float3 newSum = accumulatedColor.rgb + color;
//		float4 newAccumulatedColor = float4(newSum, newSampleCount);
//		accumulationTexture.write(newAccumulatedColor, uint2(in.position.x, in.position.y));
//		return float4(newSum / newSampleCount, 1.0);
//	} else {
//		return float4(color, 1.0);
//	}
//}

fragment float4 fragment_main(VertexOut in [[stage_in]],
							  texture2d<float, access::sample> accumulationTexture [[texture(0)]])
{
	return accumulationTexture.sample(sampler(coord::normalized), in.uv);
}



kernel void raytraceKernel(texture2d<float, access::read_write> accumulationTexture [[texture(0)]],
						   constant float2 &resolution [[buffer(0)]],
						   constant float3 &cameraPos [[buffer(1)]],
						   constant Sphere* spheres [[buffer(2)]],
						   constant int &nbSpheres [[buffer(3)]],
						   constant Triangle* triangles [[buffer(4)]],
						   constant int &nbTriangles [[buffer(5)]],
						   constant uint& frameCount [[buffer(6)]],
						   constant bool& isAccumulating [[buffer(7)]],
						   constant float3 &topLeft [[buffer(8)]],
						   constant float3 &vx [[buffer(9)]],
						   constant float3 &vy [[buffer(10)]],
						   uint2 gid [[thread_position_in_grid]])
{
	if (gid.x >= uint(resolution.x) || gid.y >= uint(resolution.y)) return;
	
	uint rngState = uint(gid.x) * 1973 + uint(gid.y) * 9277 + frameCount * 26699 + 1;
	
	float2 pixel = float2(gid);
	float3 rayOrigin = cameraPos;
	float3 pixelPos = topLeft + pixel.x * vx + pixel.y * vy;
	float3 rayDir = normalize(pixelPos - rayOrigin);
	
	const int NumRaysPerPixel = 10;
	float3 totalIncomingLight = float3(0.0);
	for (int rayIndex = 0; rayIndex < NumRaysPerPixel; rayIndex++) {
		float dx = RandomFloat01(rngState);
		float dy = RandomFloat01(rngState);
		float2 pixelSample = pixel + float2(dx, dy);
		float3 sampledDir = getRayDir(pixelSample.x, pixelSample.y, topLeft, vx, vy, rayOrigin);
		totalIncomingLight += getColor(rayOrigin, sampledDir, spheres, nbSpheres, triangles, nbTriangles, 20, 20, rngState);
	}
	float3 color = totalIncomingLight / NumRaysPerPixel;
	
	if (isAccumulating) {
		float4 previousColor = accumulationTexture.read(gid);
		float newSampleCount = previousColor.a + 1.0;
		float3 newSum = previousColor.rgb + color;
		float4 newAccumulatedColor = float4(newSum, newSampleCount);
		accumulationTexture.write(newAccumulatedColor, gid);
	} else {
		accumulationTexture.write(float4(color, 1.0), gid);
	}
}
