/*
 * layout_sa.c — fast simulated-annealing grid layout for the cave map.
 * Driven by make_map.py (--solve); not part of the app.
 *
 * stdin:
 *   N C iters seed T0 lenW minx maxx miny maxy   (box for movable rooms)
 *   N lines:  x y fixed
 *   C lines:  a b ax ay bx by     (ax,ay = compass vector at a's end, 0 0 if none)
 * stdout: N lines "x y"
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXN 400
#define MAXC 800
#define HW 0.37
#define HH 0.26

static int N, C;
static int X[MAXN], Y[MAXN], FIX[MAXN];
static int CA[MAXC], CB[MAXC], AX[MAXC], AY[MAXC], BX[MAXC], BY[MAXC];
static int INC[MAXN][64], NINC[MAXN];
static double LENW = 1.5, W_BACK = 20, W_SIDE = 4, W_HIT = 30, W_CROSS = 3.5;

static unsigned long long rs = 88172645463325252ULL;
static double rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return (rs >> 11) * (1.0 / 9007199254740992.0); }
static int rint_(int a, int b) { return a + (int)(rnd() * (b - a + 1)); }

static int sgn(int v) { return (v > 0) - (v < 0); }

static double ccost(int i) {
	int a = CA[i], b = CB[i];
	int dx = X[b] - X[a], dy = Y[b] - Y[a];
	int m = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
	double c = (m - 1) * LENW + (m > 2 ? (m - 2) * (m - 2) * 1.2 : 0);
	if (AX[i] || AY[i]) {
		if (sgn(dx) != AX[i] || sgn(dy) != AY[i])
			c += (AX[i] * dx + AY[i] * dy > 0) ? W_SIDE : W_BACK;
	}
	if (BX[i] || BY[i]) {
		if (sgn(-dx) != BX[i] || sgn(-dy) != BY[i])
			c += (BX[i] * -dx + BY[i] * -dy > 0) ? W_SIDE : W_BACK;
	}
	return c;
}

static int seg_box(double x0, double y0, double x1, double y1, double cx, double cy) {
	double dx = x1 - x0, dy = y1 - y0, t0 = 0, t1 = 1;
	double p[4] = {-dx, dx, -dy, dy};
	double q[4] = {x0 - (cx - HW - 0.04), (cx + HW + 0.04) - x0, y0 - (cy - HH - 0.04), (cy + HH + 0.04) - y0};
	for (int k = 0; k < 4; k++) {
		if (p[k] == 0) { if (q[k] < 0) return 0; }
		else {
			double t = q[k] / p[k];
			if (p[k] < 0) { if (t > t1) return 0; if (t > t0) t0 = t; }
			else { if (t < t0) return 0; if (t < t1) t1 = t; }
		}
	}
	return t0 < t1;
}

static int hit(int i, int k) {
	int a = CA[i], b = CB[i];
	if (k == a || k == b || a == b) return 0;
	int minx = X[a] < X[b] ? X[a] : X[b], maxx = X[a] < X[b] ? X[b] : X[a];
	int miny = Y[a] < Y[b] ? Y[a] : Y[b], maxy = Y[a] < Y[b] ? Y[b] : Y[a];
	if (X[k] < minx - 1 || X[k] > maxx + 1 || Y[k] < miny - 1 || Y[k] > maxy + 1) return 0;
	return seg_box(X[a], Y[a], X[b], Y[b], X[k], Y[k]);
}

static int orient(double ax, double ay, double bx, double by, double cx, double cy) {
	double v = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	return v > 1e-9 ? 1 : (v < -1e-9 ? -1 : 0);
}

static int cross(int i, int j) {
	int a = CA[i], b = CB[i], c = CA[j], d = CB[j];
	if (a == b || c == d || a == c || a == d || b == c || b == d) return 0;
	int o1 = orient(X[a], Y[a], X[b], Y[b], X[c], Y[c]);
	int o2 = orient(X[a], Y[a], X[b], Y[b], X[d], Y[d]);
	int o3 = orient(X[c], Y[c], X[d], Y[d], X[a], Y[a]);
	int o4 = orient(X[c], Y[c], X[d], Y[d], X[b], Y[b]);
	if (o1 * o2 < 0 && o3 * o4 < 0) return 1;
	/* collinear overlap counts too (lines drawn on top of each other) */
	if (o1 == 0 && o2 == 0) {
		int ax0 = X[a] < X[b] ? X[a] : X[b], ax1 = X[a] < X[b] ? X[b] : X[a];
		int ay0 = Y[a] < Y[b] ? Y[a] : Y[b], ay1 = Y[a] < Y[b] ? Y[b] : Y[a];
		int cx0 = X[c] < X[d] ? X[c] : X[d], cx1 = X[c] < X[d] ? X[d] : X[c];
		int cy0 = Y[c] < Y[d] ? Y[c] : Y[d], cy1 = Y[c] < Y[d] ? Y[d] : Y[c];
		if (ax0 < cx1 && cx0 < ax1) return 1;
		if (ay0 < cy1 && cy0 < ay1 && ax0 == ax1 && cx0 == cx1) return 1;
	}
	return 0;
}

static int mark[MAXC];

static double local(int *moved, int nm) {
	static int aff[MAXC];
	int na = 0;
	for (int m = 0; m < nm; m++)
		for (int t = 0; t < NINC[moved[m]]; t++) {
			int i = INC[moved[m]][t];
			if (!mark[i]) { mark[i] = 1; aff[na++] = i; }
		}
	double s = 0;
	for (int u = 0; u < na; u++) {
		int i = aff[u];
		s += ccost(i);
		for (int k = 0; k < N; k++) s += W_HIT * hit(i, k);
		for (int j = 0; j < C; j++) if (!mark[j]) s += W_CROSS * cross(i, j);
		for (int v = u + 1; v < na; v++) s += W_CROSS * cross(i, aff[v]);
	}
	for (int j = 0; j < C; j++)
		if (!mark[j])
			for (int m = 0; m < nm; m++) s += W_HIT * hit(j, moved[m]);
	for (int u = 0; u < na; u++) mark[aff[u]] = 0;
	return s;
}

static double total(void) {
	double s = 0;
	for (int i = 0; i < C; i++) {
		s += ccost(i);
		for (int k = 0; k < N; k++) s += W_HIT * hit(i, k);
		for (int j = i + 1; j < C; j++) s += W_CROSS * cross(i, j);
	}
	return s;
}

static int at(int x, int y) {
	for (int k = 0; k < N; k++) if (X[k] == x && Y[k] == y) return k;
	return -1;
}

int main(void) {
	long iters; unsigned seed; double T0;
	int bx0, bx1, by0, by1;
	if (scanf("%d %d %ld %u %lf %lf %d %d %d %d", &N, &C, &iters, &seed, &T0, &LENW,
	          &bx0, &bx1, &by0, &by1) != 10) return 1;
	rs ^= (unsigned long long)seed * 2654435761ULL;
	for (int k = 0; k < N; k++) if (scanf("%d %d %d", &X[k], &Y[k], &FIX[k]) != 3) return 1;
	for (int i = 0; i < C; i++) {
		if (scanf("%d %d %d %d %d %d", &CA[i], &CB[i], &AX[i], &AY[i], &BX[i], &BY[i]) != 6) return 1;
		INC[CA[i]][NINC[CA[i]]++] = i;
		if (CB[i] != CA[i]) INC[CB[i]][NINC[CB[i]]++] = i;
	}
	int freeL[MAXN], nf = 0;
	for (int k = 0; k < N; k++) if (!FIX[k]) freeL[nf++] = k;
	if (nf == 0) goto out;
	double cur = total(), best = cur;
	int BXs[MAXN], BYs[MAXN];
	memcpy(BXs, X, sizeof X); memcpy(BYs, Y, sizeof Y);
	for (long it = 0; it < iters; it++) {
		double frac = (double)it / iters;
		double T = T0 * (1 - frac) * (1 - frac) + 0.02;
		int k = freeL[rint_(0, nf - 1)];
		int ox = X[k], oy = Y[k], nx, ny;
		double r = rnd();
		if (r < 0.55) { nx = ox + rint_(-1, 1); ny = oy + rint_(-1, 1); }
		else if (r < 0.8) {
			/* next to a neighbour, on the side its exit asks for */
			int t = INC[k][rint_(0, NINC[k] - 1 < 0 ? 0 : NINC[k] - 1)];
			if (NINC[k] == 0) continue;
			int o = CA[t] == k ? CB[t] : CA[t];
			int vx = CA[t] == k ? -AX[t] : -BX[t], vy = CA[t] == k ? -AY[t] : -BY[t];
			if (CA[t] == k && (BX[t] || BY[t])) { vx = BX[t]; vy = BY[t]; }
			else if (CB[t] == k && (AX[t] || AY[t])) { vx = AX[t]; vy = AY[t]; }
			if (!vx && !vy) { vx = rint_(-1, 1); vy = rint_(-1, 1); }
			nx = X[o] + vx; ny = Y[o] + vy;
		} else { nx = ox + rint_(-3, 3); ny = oy + rint_(-3, 3); }
		if (nx == ox && ny == oy) continue;
		if (nx < bx0 || nx > bx1 || ny < by0 || ny > by1) continue;
		int other = at(nx, ny);
		if (other >= 0 && FIX[other]) continue;
		int moved[2] = {k, other}; int nm = other >= 0 ? 2 : 1;
		double before = local(moved, nm);
		X[k] = nx; Y[k] = ny;
		if (other >= 0) { X[other] = ox; Y[other] = oy; }
		double after = local(moved, nm);
		double d = after - before;
		if (d <= 0 || rnd() < exp(-d / T)) {
			cur += d;
			if (cur < best - 1e-9) { best = cur; memcpy(BXs, X, sizeof X); memcpy(BYs, Y, sizeof Y); }
		} else {
			X[k] = ox; Y[k] = oy;
			if (other >= 0) { X[other] = nx; Y[other] = ny; }
		}
	}
	memcpy(X, BXs, sizeof X); memcpy(Y, BYs, sizeof Y);
	fprintf(stderr, "best cost %.1f\n", total());
out:
	for (int k = 0; k < N; k++) printf("%d %d\n", X[k], Y[k]);
	return 0;
}
