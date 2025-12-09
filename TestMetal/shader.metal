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

#define GROUND_COLOR      float3(0.35, 0.3, 0.35)
#define SKY_COLOR_HORIZON float3(1., 1., 1.)
#define SKY_COLOR_ZENITH  float3(0.0788092, 0.36480793, 0.7264151)
#define SUN_FOCUS         500
#define SUN_INTENSITY     200
#define SUN_POS           float3(-10, 10, -500)

#define M_PI 3.14159265358979323846

//MARK: Vertex
struct VertexOut {
	float4 position [[position]];
	float2 uv;
	float2 pixelCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
							 constant float2 &resolution [[buffer(0)]]) {
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
	out.pixelCoord = out.uv * resolution;
	return out;
}

fragment float4 fragment_displayAccumulation(VertexOut in [[stage_in]],
											 texture2d<float> accumulationTexture [[texture(0)]]) {
	constexpr sampler s(address::clamp_to_edge, filter::nearest);
	float4 color = accumulationTexture.sample(s, in.uv);
	return float4(color.rgb / max(color.a, 1.0), 1.0); // Normalisation finale
}


//MARK: Struct
struct Material {
	float3 color;
	float3 emitingColor;
	float emitingStrength;
	float smoothness;
	bool isTransparent;
	float indice;
};

struct Bounds {
	float3 boundMin;
//	float   _pad0;
	float3 boundMax;
//	float   _pad1;
};

struct Node {
	int  childIndex;
	int  triangleIndex;
	int  nbTriangles;
	int  depth;
	Bounds bounds;
};

inline bool isEmptyNode(const Node n) {
    return n.childIndex == 0 && n.triangleIndex == 0 && n.nbTriangles == 0 &&
           all(n.bounds.boundMin == float3(0.0)) && all(n.bounds.boundMax == float3(0.0));
}

inline bool isNotEmptyNode(const Node n) {
    return !isEmptyNode(n);
}

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

struct Spot {
	float3 center;
	float radius;
	float3 dir;
	float fov; // En degrès
	bool blur;
	Material material;
};

struct MeshInfo {
	int firstTriangleIndex;
	int nbTriangles;
	float3 boundMin;
	float3 boundMax;
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



struct StatsGPU {
	atomic_uint onScreenTriangles;
	atomic_uint totalTriangles;
	atomic_uint trianglesTest;
};

inline void atomic_inc(device atomic_uint *p, uint v = 1) {
	atomic_fetch_add_explicit(p, v, memory_order_relaxed);
}


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

Bounds createBounds(float3 boundMin, float3 boundMax) {
	Bounds b;
	b.boundMin = boundMin;
	b.boundMax = boundMax;
	
	return b;
}

#define EMPTY_BOUNDS createBounds(float3(0.), float3(0.))

Node createNode(int childIndex, int triangleIndex, int nbTriangles, Bounds bounds) {
	Node n;
	n.childIndex = childIndex;
	n.triangleIndex = triangleIndex;
	n.nbTriangles = nbTriangles;
	n.bounds = bounds;
	
	return n;
}

#define EMPTY_NODE createNode(0, 0, 0, EMPTY_BOUNDS)

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
float3 rayAt(float3 origin, float3 dir, float t) {
	return origin + t * dir;
}

float3 rayAt(Ray ray, float t) {
	return rayAt(ray.origin, ray.dir, t);
}

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
	
//	if (dot(n, dir) > 0) return -1.;
	
	// Calcul du déterminant
	float3 pvec = cross(dir, AC);
	float det   = dot(AB, pvec);
	
	// Rayon parallèle ou triangle dos tourné (selon que l’on veut culler ou pas)
//	if (fabs(det) < 0)
//		return -1.0;
	
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

bool intersectBoundingBox(Ray ray, float3 BoundMin, float3 BoundMax) {
	float3 invDir = 1.0 / ray.dir;
	float3 t0 = (BoundMin - ray.origin) * invDir;
	float3 t1 = (BoundMax - ray.origin) * invDir;
	
	float3 tMinVec = min(t0, t1);
	float3 tMaxVec = max(t0, t1);
	
	float tMin = max(max(tMinVec.x, tMinVec.y), tMinVec.z);
	float tMax = min(min(tMaxVec.x, tMaxVec.y), tMaxVec.z);
	
	return tMax >= max(tMin, 0.0);
}

bool intersectBoundingBox(Ray ray, Bounds bound) {
	return intersectBoundingBox(ray, bound.boundMin, bound.boundMax);
}

bool intersectMesh(Ray ray, MeshInfo mesh) {
	return intersectBoundingBox(ray, mesh.boundMin, mesh.boundMax);
}



float intersectSpot(Spot spot, Ray ray) {
	float3 oc = ray.origin - spot.center;
	float a = dot(ray.dir, ray.dir);
	float b = 2.0 * dot(oc, ray.dir);
	float c = dot(oc, oc) - spot.radius * spot.radius;
	float discriminant = b * b - 4.0 * a * c;
	
	if (discriminant < 0.0) return -1.0;
	
	float t1 = (-b - sqrt(discriminant)) / (2.0 * a);
	float t2 = (-b + sqrt(discriminant)) / (2.0 * a);
	float t = min(t1, t2);
	
	if (t < 0.0) return -1.0;
	
	// Vérifier que le point d'intersection est dans le cône
	float3 hitPoint = rayAt(ray, t);
	float3 toLight = normalize(hitPoint - spot.center);
	float cosAngle = dot(toLight, normalize(spot.dir));
	float cosFov = cos(spot.fov * (M_PI / 180.0));
	
	if (cosAngle < cosFov) return -1.0;
	
	return t;
}

//MARK: Ray
struct RayHit RayHit(bool hit, float t, float3 n, Material material) {
	struct RayHit r;
	r.hit = hit;
	r.t = t;
	r.n = normalize(n);
	r.material = material;
	
	return r;
}


//MARK: rayCollision
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

struct RayHit rayCollisionMeshes(Ray ray, constant Triangle* triangles, int _nbTriangles, constant MeshInfo* meshes, int nbMeshes) {
	float t = MAX_T;
	Triangle triangle;
	
	for (int i = 0; i < nbMeshes; i++) {
		MeshInfo mesh = meshes[i];
		if (!intersectMesh(ray, mesh)) { continue; }
		
		for (int j = mesh.firstTriangleIndex; j < mesh.firstTriangleIndex + mesh.nbTriangles; j++) {
			float _t = intersectTriangle(triangles[j], ray);
			
			if (_t > EPS && _t < t) {
				t = _t;
				triangle = triangles[j];
			}
		}
	}
	
	return RayHit(t != MAX_T, t, triangle.n, triangle.material);
}

struct RayHit rayCollisionSpot(Ray ray, constant Spot* spots, int nb) {
	float t = MAX_T;
	float angle = 0;
	Spot spot;
	float _t;
	for (int i = 0; i < nb; i++) {
		_t = intersectSpot(spots[i], ray);
		float _angle = acos(dot(ray.dir, normalize(spots[i].center - ray.origin))) * (180.0 / M_PI);
		if (_t > 0 && _t < t && _angle < spots[i].fov) {
			spot = spots[i];
			t = _t;
			angle = _angle;
		}
	}
	
	if (t == MAX_T) {
		return RayHit(false, MAX_T, float3(0.), WHITE_MAT);
	}
	// Conversion manuelle en radians
	float angleRad = angle * (M_PI / 180.0);
	float blurFactor = spot.blur ? cos(angleRad * spot.fov / 90.0) : 1.0;
	Material m = createMaterial(
								spot.material.color,
								spot.material.emitingColor,
								blurFactor * spot.material.emitingStrength,
								spot.material.smoothness
								);
	return RayHit(true, t, rayAt(ray, t) - spot.center, m);
}

//MARK: rayCollosionAll
struct RayHit rayCollisionAllTriangle(Ray ray, constant Triangle* triangles, int nbTriangles) {
	struct RayHit rayHit = rayCollisionTriangles(ray, triangles, nbTriangles);
	
	if (!rayHit.hit) return BLANK_RAY;
	
	struct RayHit rayH;
	
	rayH.hit = true;
	rayHit.material = rayHit.material;
	rayH.n = rayHit.n;
	
	return rayH;
}

struct RayHit rayCollosionAllMesh(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant MeshInfo* meshes, int nbMeshes) {
	struct RayHit rayHitB = rayCollisionSpheres(ray, spheres, nbSpheres);
	struct RayHit rayHitT = rayCollisionMeshes(ray, triangles, nbTriangles, meshes, nbMeshes);
	
	
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

Node rayCollisionNodes(Ray ray, Node parent, constant Node* nodes, int nbNode) {
	if (!intersectBoundingBox(ray, parent.bounds)) return EMPTY_NODE;
	if (parent.childIndex == 0) { return parent; }
	
	Node n1 = rayCollisionNodes(ray, nodes[parent.childIndex], nodes, nbNode);
	if (isNotEmptyNode(n1)) { return n1; }
	Node n2 = rayCollisionNodes(ray, nodes[parent.childIndex + 1], nodes, nbNode);
	if (isNotEmptyNode(n2)) { return n2; }
	
	return EMPTY_NODE;
}

struct RayHit rayCollisionNodes(Ray ray, constant Node* nodes, int nbNodes, constant Triangle* triangles, int nbTriangles) {
	float t = MAX_T;
	float3 n = float3(0.);
	Material mat = WHITE_MAT;
	bool hit = false;
	
	Node stack[10];
	int stackIndex = 0;
	stack[stackIndex++] = nodes[0];
	
	while (stackIndex > 0) {
		Node node = stack[--stackIndex];
		
		if (!intersectBoundingBox(ray, node.bounds)) continue;
		
		if (node.childIndex == 0) { // Leaf
			for (int j = node.triangleIndex; j < node.triangleIndex + node.nbTriangles; j++) {
				float _t = intersectTriangle(triangles[j], ray);
				if (_t > EPS && _t < t) {
					t = _t;
					n = triangles[j].n;
					mat = triangles[j].material;
					hit = true;
				}
			}
		} else {
			stack[stackIndex++] = nodes[node.childIndex];
			stack[stackIndex++] = nodes[node.childIndex + 1];
		}
	}
	
	
	if (t == MAX_T) {
		return RayHit(false, MAX_T, float3(0.), WHITE_MAT);
	}
	
	if (hit) {
		return RayHit(true, t, n, mat);
	}
	
	return BLANK_RAY;
}


struct RayHit rayCollisionAllV2(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant MeshInfo* meshes, int nbMeshes, thread const Spot* spots, int nbSpots) {
	float t = MAX_T;
	float3 n = float3(0.);
	Spot spot;
	float angle;
	bool isSpot = false;
	Material mat = WHITE_MAT;
	bool hit = false;
	
	// Recherche sur sphères
	for (int i = 0; i < nbSpheres; i++) {
		float _t = intersectSphere(spheres[i], ray);
		if (_t > EPS && _t < t) {
			t = _t;
			n = rayAt(ray, t) - spheres[i].center;
			mat = spheres[i].material;
			hit = true;
		}
	}
	
	// Recherche sur tous les triangles des meshes (avec bbox d'abord)
	for (int m = 0; m < nbMeshes; m++) {
		MeshInfo mesh = meshes[m];
		if (!intersectBoundingBox(ray, mesh.boundMin, mesh.boundMax)) continue;
		for (int j = mesh.firstTriangleIndex; j < mesh.firstTriangleIndex + mesh.nbTriangles; j++) {
			float _t = intersectTriangle(triangles[j], ray);
			if (_t > EPS && _t < t) {
				t = _t;
				n = triangles[j].n;
				mat = triangles[j].material;
				hit = true;
			}
		}
	}
	
	// Recherche des spots
	for (int i = 0; i < nbSpots; i++) {
		float _t = intersectSpot(spots[i], ray);
		if (_t > 0 && _t < t) {
			t = _t;
			n = rayAt(ray, t) - spots[i].center;
			mat = spots[i].material;
			hit = true;
			
			// Calcul de l'atténuation
			float3 hitPoint = rayAt(ray, t);
			float3 toLight = normalize(hitPoint - spots[i].center);
			float cosAngle = dot(toLight, normalize(spots[i].dir));
			float cosFov = cos(spots[i].fov * (M_PI / 180.0));
			float atten = (cosAngle - cosFov) / (1.0 - cosFov);
			float blur = spots[i].blur ? pow(atten, 4.0) : 1.0;
			
			mat.emitingStrength *= blur;
		}
	}
	
	if (t == MAX_T) {
		return RayHit(false, MAX_T, float3(0.), WHITE_MAT);
	}
	
	if (isSpot) {
		float blurFactor = spot.blur ? cos(angle * spot.fov / 90.0) : 1.0;
		Material m = createMaterial(
									spot.material.color,
									spot.material.emitingColor,
									blurFactor * spot.material.emitingStrength,
									spot.material.smoothness
									);
		return RayHit(true, t, rayAt(ray, t) - spot.center, m);
	}
	
	if (hit) {
		return RayHit(true, t, n, mat);
	}
	
	return BLANK_RAY;
}

struct RayHit rayCollisionAllV3(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant Node* nodes, int nbNodes) {
	float t = MAX_T;
	float3 n = float3(0.);
	Material mat = WHITE_MAT;
	bool hit = false;
	
	// Recherche sur sphères
	for (int i = 0; i < nbSpheres; i++) {
		float _t = intersectSphere(spheres[i], ray);
		if (_t > EPS && _t < t) {
			t = _t;
			n = rayAt(ray, t) - spheres[i].center;
			mat = spheres[i].material;
			hit = true;
		}
	}
	
	struct RayHit rhit = rayCollisionNodes(ray, nodes, nbNodes, triangles, nbTriangles);
	
	if (rhit.t < t) {
		t = rhit.t;
		n = rhit.n;
		mat = rhit.material;
		hit = rhit.hit;
	}
	
	if (t == MAX_T) {
		return RayHit(false, MAX_T, float3(0.), WHITE_MAT);
	}
	
	if (hit) {
		return RayHit(true, t, n, mat);
	}
	
	return BLANK_RAY;
}

float3 applyBeer(float3 throughput, float3 absorption, float distance) {
	float3 T = exp(-absorption * max(distance, 0.0));
	return throughput * T;
}


float3 lerp(float3 a, float3 b, float p) {
	return p * a + (1 - p) * b;
}

//MARK: Color
float3 GetEnvironmentLight(Ray ray)
{
//	if (!EnvironmentEnabled) {
//		return 0;
//	}
	
	float3 sunDir = normalize(SUN_POS);
	float sun = pow(max(0., dot(ray.dir, sunDir)), SUN_FOCUS) * SUN_INTENSITY;
	
	float skyGradientT = pow(smoothstep(0, 0.4, ray.dir.y), 0.35);
	float groundToSkyT = smoothstep(-0.01, 0, ray.dir.y);
	float3 skyGradient = lerp(SKY_COLOR_HORIZON, SKY_COLOR_ZENITH, skyGradientT);
	
	// Nuages par pseudo bruit sinusoïdal
	float cloudNoise = sin(ray.dir.x * 40.) * sin(ray.dir.z * 40.);
	float clouds = smoothstep(0.2, 0.5, cloudNoise);
	float3 cloudColor = float3(1.0) * clouds * 0.5;
	
	float3 composite = lerp(GROUND_COLOR, skyGradient, groundToSkyT) + sun + cloudColor;

	return composite;
}

float3 refractRay(float3 d, float3 n, float n1, float n2) {
	float eta = n1 / n2;
	float cosi = clamp(-dot(d, n), -1.0, 1.0);
	float k = 1.0 - eta*eta*(1.0 - cosi*cosi);
	
	if (k < 0.0) {
		return float3(0.0);
	} else {
		return normalize(eta*d + (eta*cosi - sqrt(k))*n);
	}
}

float lengthSquared(float3 v) {
	return v.x * v.x + v.y * v.y + v.z * v.z;
}

float3 refractP(float3 uv, float3 n, float etai_over_etat) {
	float cos_theta = min(dot(-uv, n), 1.0);
	float3 r_out_perp =  etai_over_etat * (uv + cos_theta*n);
	float3 r_out_parallel = -sqrt(abs(1.0 - lengthSquared(r_out_perp))) * n;
	return r_out_perp + r_out_parallel;
}

//MARK: getColor
float3 getColor(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant MeshInfo* meshes, int nbMeshes, constant Node* nodes, int nbNodes, const thread Spot* spots, int nbSpots, int maxDepth, thread uint &rngState) {
	float3 incomingLight = float3(0.);
	float3 color = float3(1.);
	
	for (int i = 0; i < maxDepth; i++) {
		struct RayHit rayHit = rayCollisionAllV2(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes, spots, nbSpots);
		
		if (!rayHit.hit || rayHit.t >= MAX_T) {
			incomingLight += SKY_COLOR_ZENITH * color;
			break;
		}
		
		float3 hitPos = rayAt(ray, rayHit.t);
		
		// Carrelage sol
//		if (abs(hitPos.y) < 0.2 && abs(rayHit.n.y) > 0.9) {
//			float gridSize = 2.0;
//			int xi = int(floor(hitPos.x / gridSize));
//			int zi = int(floor(hitPos.z / gridSize));
//			int parity = (xi + zi) & 1;
//			
//			float3 lightGray = float3(0.8);
//			float3 darkGray  = float3(0.2);
//			rayHit.material.color *= mix(lightGray, darkGray, parity);
//		}
		
		Material material = rayHit.material;
		
		// Décale toujours l'origine suivant la direction
		bool outside = dot(ray.dir, rayHit.n) < 0.0;
		float3 orientedN = outside ? -rayHit.n : rayHit.n;
		
		
		if (material.isTransparent) {
			ray.origin = hitPos + rayHit.n * EPS * sign(dot(ray.dir, rayHit.n));
			float n1 = outside ? 1.0 : material.indice;
			float n2 = outside ? material.indice : 1.0;
			float over = n2 / n1;
			
			ray.dir = normalize(refractP(ray.dir, rayHit.n, over));
			color *= material.color;
			
		} else {
			ray.origin = hitPos + rayHit.n * EPS;
			float3 specularDir = reflect(ray.dir, rayHit.n);
			float3 diffuseDir  = normalize(rayHit.n + RandomDirection(rngState));
			
			// Lumière émise par le matériau touché (lampe, spot, etc.)
			float3 emitedLight = material.emitingColor * material.emitingStrength;
			incomingLight += emitedLight * color;
			
			color *= material.color;
			
			// Choix direction rebond
			if (material.smoothness > 1 - 1e-3) {
				ray.dir = specularDir;
			} else if (material.smoothness < 1e-3) {
				ray.dir = diffuseDir;
			} else {
				ray.dir = normalize(lerp(specularDir, diffuseDir, material.smoothness));
			}
		}
	}
	
	if (any(isnan(incomingLight))) { return float3(0.0, 10000000., .0); }
	
	return incomingLight;
}


float3 getOnlyColorTriangle(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant MeshInfo* meshes, int nbMeshes) {
	struct RayHit rayHit = rayCollosionAllMesh(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes);
	
	if (rayHit.hit) {
		return rayHit.material.emitingStrength < EPS ? rayHit.material.color : rayHit.material.emitingColor;
	}
	
	return SKY_COLOR_ZENITH;
}

float3 getOnlyColorMesh(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant MeshInfo* meshes, int nbMeshes, device StatsGPU* stats) {
	struct RayHit rayHit = rayCollosionAllMesh(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes);
	
	if (rayHit.hit) {
		atomic_inc(&stats->trianglesTest);
		return rayHit.material.emitingStrength < EPS ? rayHit.material.color : rayHit.material.emitingColor;
	}
	
	return SKY_COLOR_ZENITH;
}

float3 getOnlyColorV3(Ray ray, constant Sphere* spheres, int nbSpheres, constant Triangle* triangles, int nbTriangles, constant Node* nodes, int nbNodes) {
	struct RayHit rayHit = rayCollisionAllV3(ray, spheres, nbSpheres, triangles, nbTriangles, nodes, nbNodes);
	
	if (rayHit.hit) {
		return rayHit.material.emitingStrength < EPS ? rayHit.material.color : rayHit.material.emitingColor;
	}
	
	return SKY_COLOR_ZENITH;
}


float3 getRayDir(float x, float y, float3 topLeft, float3 vx, float3 vy, float3 cameraPos) {
	float3 pointOnViewport = topLeft + x * vx + y * vy;
	
	return normalize(pointOnViewport - cameraPos);
}

//MARK: Main
fragment float4 fragment_main(VertexOut in [[stage_in]],
							  constant float2 &resolution [[buffer(0)]],
							  constant float3 &cameraPos [[buffer(1)]],
							  texture2d<float, access::read_write> accumulationTexture [[texture(0)]],
							  constant float3 &topLeft [[buffer(13)]],
							  constant float3 &vx [[buffer(14)]],
							  constant float3 &vy [[buffer(15)]],
							  constant uint2 &tileOrigin [[buffer(16)]],
							  constant uint2 &tileSize [[buffer(17)]],
							  constant int &maxBounce [[buffer(18)]],
							  constant int &maxBouncePreview [[buffer(19)]],
							  constant int &raysPerPixel [[buffer(20)]],
							  device StatsGPU* stats [[buffer(22)]],
							  
							  constant Sphere* spheres [[buffer(2)]],
							  constant int &nbSpheres [[buffer(3)]],
							  constant Triangle* triangles [[buffer(4)]],
							  constant int &nbTriangles [[buffer(5)]],
							  constant MeshInfo* meshes [[buffer(6)]],
							  constant int &nbMeshes [[buffer(7)]],
							  constant Node* nodes [[buffer(8)]],
							  constant int &nbNodes [[buffer(9)]],
							  
							  constant uint& frameCount [[buffer(10)]],
							  constant bool& isAccumulating [[buffer(11)]],
							  constant bool& enableRayTracing [[buffer(12)]],
							  constant bool& enableBetterRayTracing [[buffer(21)]])
							  
{
	float2 pixel = in.uv * resolution;
	
	// Vérifiez si nous sommes en mode tuile valide
	if (tileSize.x > 0 && tileSize.y > 0) {
		if (pixel.x < tileOrigin.x || pixel.x >= tileOrigin.x + tileSize.x ||
			pixel.y < tileOrigin.y || pixel.y >= tileOrigin.y + tileSize.y) {
			discard_fragment();
		}
	}
	
	thread uint rngState = uint(uint(in.position.x) * uint(1973) + uint(in.position.y) * uint(9277) + uint(frameCount) * uint(26699)) | uint(1);
	
	uint2 coord = uint2(pixel);

	
	float3 rayOrigin = cameraPos;
	float3 rayDir = normalize(topLeft + pixel.x * vx + pixel.y * vy - cameraPos);
	
	Ray ray = createRay(rayOrigin, rayDir);
	float3 color;
	
	if (enableBetterRayTracing) {
		float3 totalIncomingLight = float3(0.);
		for (int rayIndex = 0; rayIndex < raysPerPixel; rayIndex++) {
			float dx = RandomFloat01(rngState);
			float dy = RandomFloat01(rngState);
			
			float2 pixelSample = pixel + float2(dx, dy);
			rayDir = normalize(topLeft + pixelSample.x * vx + pixelSample.y * vy - cameraPos);
			ray.dir = rayDir;
			
			float3 finalColor = getColor(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes, nodes, nbNodes, nullptr, 0, maxBounce, rngState);
			totalIncomingLight += finalColor;
		}
		color = totalIncomingLight / raysPerPixel;
	} else if (enableRayTracing) {
		color = getColor(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes, nodes, nbNodes, nullptr, 0, maxBouncePreview, rngState);
	} else {
		color = getOnlyColorV3(ray, spheres, nbSpheres, triangles, nbTriangles, nodes, nbNodes);
//		color = getOnlyColorMesh(ray, spheres, nbSpheres, triangles, nbTriangles, meshes, nbMeshes, stats);
	}
	
	if (isAccumulating) {
		float4 accumulatedColor = accumulationTexture.read(coord);
		float newSampleCount = accumulatedColor.a + 1.0;
		float3 newSum = accumulatedColor.rgb + color;
		accumulationTexture.write(float4(newSum, newSampleCount), coord);
		
		return float4(newSum / newSampleCount, 1.0);
	} else {
		return float4(color, 1.0);
	}
}

