import matplotlib.pyplot as plt
import numpy as np

import matplotlib.animation as animation

g_raw = 9.81
show_trace = False

#clk_rate = 100_000000
clk_rate = 100
beats = 10

"""
t is given in number the cycles
"""

g = g_raw / clk_rate / clk_rate



#pat = [4, 3, 2]
pat = [5, 3, 1]
#pat = [3, 3, 3]
num_balls = len(pat)

s_per_beat = 0.2
cyc_per_beat = round(s_per_beat * clk_rate) 
dist = 0.1

throws = [0, 1, 2, 3, 4, 5]
max_t = [ p * cyc_per_beat for p in throws ]
vx = [ dist / t if t != 0 else 0 for t in max_t ]
vy  = [ g * t / 2 for t in max_t ]

print(max_t)
print(vx)
print(vy)

ts = np.arange(0, cyc_per_beat * beats+1)

xs = [ [] for _ in range(num_balls) ]
ys = [ [] for _ in range(num_balls) ]

t_start = [ 0 for _ in range(num_balls) ]
hand = [ 0 if (i&1) == 0 else 1 for i in range(num_balls) ]
throw = [ 0 for _ in range(num_balls) ]

hidx = 0
pidx = 0
queue = [ -1 for _ in range(max(pat)) ]
for i in range(num_balls):
    queue[i] = i

counter = 0
maxi = 0
for t in ts:
    if counter == 0:
        b = queue[0]

        t_start[b] = t
        hand[b] = hidx
        hidx = 0 if hidx == 1 else 1
        throw[b] = pat[pidx]
        pidx = 0 if pidx == len(pat)-1 else pidx + 1
        print('ball', b, hand[b], throw[b])

        queue = queue[1:] + [0]
        queue[throw[b]-1] = b
    counter = counter+1 if counter+1 < cyc_per_beat else 0 


    for i in range(num_balls):
        p = throw[i]

        dt = t - t_start[i]
        nx = vx[p] * dt if hand[i] == 0 else dist - vx[p] * dt
        ny = vy[p] * dt - 0.5 * g * dt * dt
        maxi = max(maxi, dt)
        if counter == 1:
            print('\t', round(nx,2), round(ny,2))

        xs[i].append(nx)
        ys[i].append(ny)








# matploblib stuff

fig, ax = plt.subplots()
scat = [ ax.scatter(xs[i], ys[i], s=30, label=f'ball {i}') for i in range(num_balls) ]
ax.set(xlim=[0, dist], ylim=[0, np.max(ys) + 0.1], xlabel='x [m]', ylabel='y [m]')
ax.legend()


def update(frame):
    for i in range(num_balls):
        if show_trace:
            x = xs[i][:frame]
            y = ys[i][:frame]
        else:
            x = xs[i][frame]
            y = ys[i][frame]

        data = np.stack([x, y]).T
        scat[i].set_offsets(data)
    return scat[0]

ani = animation.FuncAnimation(fig=fig, func=update, frames=len(ts), interval=1000/clk_rate)
plt.show()
