//
//  split.c
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 19/12/2025.
//

#include "split.h"
#include <stdio.h>
#include <stdlib.h>
#include "stdbool.h"

struct float3 {
	float x, y, z;
};
typedef struct float3 float3;
const float3 empty_float3 = (float3){.0, .0, .0};


struct Bounds {
	float3 boundMin, boundMax;
};
typedef struct Bounds Bounds;
const Bounds empty_bound = (Bounds){empty_float3, empty_float3};

float3 getBarycentre(Bounds bound) {
	return (float3){(bound.boundMin.x + bound.boundMax.x) / 2, (bound.boundMin.y + bound.boundMax.y) / 2, (bound.boundMin.z + bound.boundMax.z) / 2};
}

struct Triangle {
	float3 A, B, C;
};
typedef struct Triangle Triangle;


float3 getBarycentreT(Triangle t) {
	return (float3){
		(t.A.x + t.B.x + t.C.x) / 3,
		(t.A.y + t.B.y + t.C.y) / 3,
		(t.A.z + t.B.z + t.C.z) / 3
	};
}


struct Node {
	int32_t childIndex;
	int32_t triangleIndex;
	int32_t nbTriangles;
	int32_t depth;
	Bounds bounds;
};
typedef struct Node Node;

struct NodeVector {
	Node* nodes;
	int capacitee;
	int taille;
};
typedef struct NodeVector NodeVector;
typedef NodeVector Vector;

Vector* createVector() {
	Vector* v = malloc(sizeof(Vector));
	v->nodes = malloc(sizeof(Node));
	v->capacitee = 1;
	v->taille = 0;
	
	return v;
}

void vectorResize(Vector* v, int s) {
	if (v->capacitee <= s) return ;
	
	Node* n = malloc(s * sizeof(Node));
	for (int i = 0; i < v->taille; i++) {
		n[i] = v->nodes[i];
	}
	free(v->nodes);
	v->nodes = n;
	v->capacitee = s;
}

void vectorAdd(Vector* v, Node node) {
	if (v->taille == v->capacitee) vectorResize(v, 2 * v->capacitee);
	v->nodes[v->taille] = node;
	v->taille++;
}

void swap(Triangle* t, int i, int j) {
	Triangle tmp = t[i];
	t[i] = t[j];
	t[j] = tmp;
}


void split(Node* node, Triangle* triangles, int nbTriangle, Vector nodes, int depth, int maxDepth) {
	if (depth >= maxDepth || node->nbTriangles <= 2) return;
	
	int start = node->triangleIndex;
	int count = node->nbTriangles;
	int end = start + count;
	
	float dx = node->bounds.boundMax.x - node->bounds.boundMin.x;
	float dy = node->bounds.boundMax.y - node->bounds.boundMin.y;
	float dz = node->bounds.boundMax.z - node->bounds.boundMin.z;
	float3 bar = getBarycentre(node->bounds);
	int side = 0;
	float center = .0;
	if (dx > dy) {
		if (dx > dz) {
			side = 1;
			center = bar.x;
		} else {
			side = 3;
			center = bar.z;
		}
	} else {
		if (dy > dz) {
			side = 2;
			center = bar.y;
		} else {
			side = 3;
			center = bar.z;
		}
	}
	
	int leftCount = 0;
	int i = start;
	int j = end - 1;
	while (i <= j) {
		Triangle t = triangles[i];
		float3 b = getBarycentreT(t);
		bool goesLeft = false;
		switch (side) {
			case 1:
				goesLeft = b.x < center;
				break;
			case 2:
				goesLeft = b.y < center;
				break;
				
			default:
				goesLeft = b.z < center;
				break;
		}
		
		if (goesLeft) {
			i++;
		} else {
			swap(triangles, i, j);
			j--;
		}
	}
	leftCount = i - count;
	
	if (leftCount == 0 || leftCount == count) {
		return;
	}
	
	int rightCount = count - leftCount;
	Node left = (Node){0, start, leftCount, depth+1, empty_bound};
	Node right = (Node){0, start+leftCount, rightCount, depth+1, empty_bound};
}
