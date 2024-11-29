import numpy as np
import itertools

# Load the arrays from the npz file
loaded = np.load('../sim/sim_build/model_balls.npz')

# Access arrays using their keys
loaded_xs = np.array([loaded['xs0'], loaded['xs1'], loaded['xs2']])
loaded_ys = np.array([loaded['ys0'], loaded['ys1'], loaded['ys2']])

# Example of using the loaded arrays
#print("Loaded xs:", loaded_xs)
#print("Loaded ys:", loaded_ys)

xs = loaded_xs.T
ys = loaded_ys.T

t = xs.shape[0]
counts = {}
for i in range(t):
    num_balls = xs.shape[1]

    model_balls_x = xs[i]
    model_balls_y = ys[i]

    real_balls_x = xs[i] + np.random.rand(num_balls) * 100
    real_balls_y = ys[i] + np.random.rand(num_balls) * 100
    #real_balls_x = xs[i] + np.ones(num_balls) * 20
    #real_balls_y = ys[i] + np.ones(num_balls) * 10


    # brute force
    arr = np.arange(num_balls)
    permutations = list(itertools.permutations(arr))

    mini = None
    best = None
    alts = []
    for p in permutations:
        cur = 0
        for i, j in enumerate(p):
            cur += (model_balls_x[i] - real_balls_x[j])**2 \
                + (model_balls_y[i] - real_balls_y[j])**2
        EPS = 1e-6
        if mini is None or cur < mini-EPS:
            mini = cur
            best = p
            alts = [p]
        elif cur < mini+EPS:
            alts.append(p)

    best = tuple(int(x) for x in best)
    alts = [ tuple(int(x) for x in alt) for alt in alts ]
    if best not in counts:
        counts[best] = 0
    counts[best] += 1

    # hungarian
    A = [
        [0] + [ (model_balls_x[i] - real_balls_x[j])**2 \
            + (model_balls_y[i] - real_balls_y[j])**2 for j in range(num_balls) ]
        for i in range(num_balls)
    ]
    A.insert(0, [ 0 for j in range(num_balls+1) ])

    u = [ 0 for _ in range(num_balls+1) ]
    v = [ 0 for _ in range(num_balls+1) ]
    p = [ 0 for _ in range(num_balls+1) ]
    way = [ 0 for _ in range(num_balls+1) ]
    for i in range(1, num_balls+1):
        p[0] = i
        j0 = 0
        minv = [ 1e9 for _ in range(num_balls+1) ]
        used = [ False for _ in range(num_balls+1) ]
        while True:
            used[j0] = True
            i0 = p[j0]
            delta = 1e9
            j1 = None
            for j in range(1, num_balls+1):
                if not used[j]:
                    cur = A[i0][j]-u[i0]-v[j];
                    if cur < minv[j]:
                        minv[j] = cur
                        way[j] = j0
                    if minv[j] < delta:
                        delta = minv[j]
                        j1 = j
            for j in range(num_balls+1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta;
            j0 = j1;
            if p[j0] == 0:
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
            if j0 == 0:
                break

    ans = [ None for _ in range(num_balls+1) ];
    for j in range(num_balls+1):
        ans[p[j]] = j;

    out = tuple(x-1 for x in ans[1:])
    #print(best, out, best == out)
    if out not in alts:
        print(best, mini, out, -v[0])

print(counts)
