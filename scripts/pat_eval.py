import numpy as np
import itertools

def cost(x1, y1, x2, y2):
    return (x1 - x2) ** 2 + (y1 - y2) ** 2;

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

    #model_balls_x = [0, 100, 500];
    #model_balls_y = [0, 100, 500];
    #real_balls_x = [110, 510, 10];
    #real_balls_y = [110, 510, 10];

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
        [
            0 if i == 0 or j == 0 else
                cost(model_balls_x[i-1], model_balls_y[i-1],
                     real_balls_x[j-1], real_balls_y[j-1])
            for j in range(num_balls+1)
        ]
        for i in range(num_balls+1)
    ]

    # hungarian cp-alg
    u = [ 0 for _ in range(num_balls+1) ]
    v = [ 0 for _ in range(num_balls+1) ]
    p = [ 0 for _ in range(num_balls+1) ]
    way = [ 0 for _ in range(num_balls+1) ] # state INIT
    # state: FORI_INIT
    for i in range(1, num_balls+1): # state FORI_CHECK
        p[0] = i
        j0 = 0
        minv = [ 1e9 for _ in range(num_balls+1) ]
        used = [ False for _ in range(num_balls+1) ] # state FORI_BODY
        while True:
            used[j0] = True
            i0 = p[j0]
            delta = 1e9
            j1 = None # state WHILE1_BODY1
            # state FORJ1_INIT
            for j in range(1, num_balls+1): # state FORJ1_CHECK
                if not used[j]: # state FORJ1_BODY
                    cur = A[i0][j]-u[i0]-v[j];
                    if cur < minv[j]:
                        minv[j] = cur
                        way[j] = j0
                    if minv[j] < delta:
                        delta = minv[j]
                        j1 = j
                # state FORJ1_UPDATE
            for j in range(num_balls+1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta;
            j0 = j1                     # state WHILE1_BODY2
            if p[j0] == 0: # state WHILE1_CHECK
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1 # state WHILE2_BODY
            if j0 == 0: # state WHILE2_CHECK
                break
        # state FORI_UPDATE

    ans = [ None for _ in range(num_balls) ];
    for j in range(1, num_balls+1):
        ans[p[j] - 1] = j - 1;              # state ANS

    # inspect
    ans = tuple(ans)
    #print(best, mini, ans, -v[0])
    if ans not in alts:
        print(best, mini, ans, -v[0])


    # hungarian cp-alg
    u = [ 0 for _ in range(num_balls+1) ]
    v = [ 0 for _ in range(num_balls+1) ]
    p = [ 0 for _ in range(num_balls+1) ]
    way = [ 0 for _ in range(num_balls+1) ] # state INIT

    i = None
    state = 'FORI_INIT'
    while True:
        # state: FORI_INIT
        if state == 'FORI_INIT':
            i = 1
            state = 'FORI_CHECK'
        elif state == 'FORI_CHECK':
            if i < num_balls+1:
                state = 'FORI_BODY'
            else:
                state = 'ANS'
        elif state == 'FORI_BODY':
            p[0] = i
            j0 = 0
            minv = [ 1e9 for _ in range(num_balls+1) ]
            used = [ False for _ in range(num_balls+1) ] # state FORI_BODY
            state = 'WHILE1_BODY1'
        elif state == 'WHILE1_BODY1':
            used[j0] = True
            i0 = p[j0]
            delta = 1e9
            j1 = None # state WHILE1_BODY1
            state = 'FORJ1_INIT'
        elif state == 'FORJ1_INIT':
            j = 1
            state = 'FORJ1_CHECK'
        elif state == 'FORJ1_CHECK':
            if j < num_balls+1:
                state = 'FORJ1_BODY'
            else:
                state = 'WHILE1_BODY2'
        elif state == 'FORJ1_BODY':
            if not used[j]: # state FORJ1_BODY
                cur = A[i0][j]-u[i0]-v[j];
                if cur < minv[j]:
                    minv[j] = cur
                    way[j] = j0
                if minv[j] < delta:
                    delta = minv[j]
                    j1 = j
            state = 'FORJ1_UPDATE'
        elif state == 'FORJ1_UPDATE':
            j += 1
            state = 'FORJ1_CHECK'
        elif state == 'WHILE1_BODY2':
            for j in range(num_balls+1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minv[j] -= delta;
            j0 = j1                     # state WHILE1_BODY2
            state = 'WHILE1_CHECK'
        elif state == 'WHILE1_CHECK':
            if p[j0] == 0: # state WHILE1_CHECK
                state = 'WHILE2_BODY'
            else:
                state = 'WHILE1_BODY1'
        elif state == 'WHILE2_BODY':
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1 # state WHILE2_BODY
            state = 'WHILE2_CHECK'
        elif state == 'WHILE2_CHECK':
            if j0 == 0:
                state = 'FORI_UPDATE'
            else:
                state = 'WHILE2_BODY'
        elif state == 'FORI_UPDATE':
            i += 1
            state = 'FORI_CHECK'
        elif state == 'ANS':
            ans2 = [ None for _ in range(num_balls) ];
            for j in range(1, num_balls+1):
                ans2[p[j] - 1] = j - 1;              # state ANS
            ans2 = tuple(ans2)
            assert ans == ans2
            break

print(counts)
