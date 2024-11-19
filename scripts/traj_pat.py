import matplotlib.pyplot as plt
import numpy as np

import matplotlib.animation as animation

g = 9.81
#show_trace = True
show_trace = False



#pat = [4, 3, 2]
#pat = [5, 3, 1]
pat = [3, 3, 3]
num_balls = len(pat)

s_per_beat = 0.2
dist = 0.1

throws = [0, 1, 2, 3, 4, 5]
max_t = [ p * s_per_beat for p in throws ]
vx = [ dist / t if t != 0 else 0 for t in max_t ]
vy  = [ g * t / 2 for t in max_t ]

print(max_t)
print(vx)
print(vy)

fig, ax = plt.subplots()
fps = 60

t_max = num_balls * max(max_t)
ts = np.linspace(0, t_max, round(t_max * fps) + 1)

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

for t in ts:
    frac_beat = t / s_per_beat
    if abs(frac_beat - round(frac_beat)) < 1e-6:
        print('hit!', round(frac_beat))

        b = queue[0]

        t_start[b] = t
        hand[b] = hidx
        hidx = 0 if hidx == 1 else 1
        throw[b] = pat[pidx]
        pidx = 0 if pidx == len(pat)-1 else pidx + 1
        print('ball', b, hand[b], throw[b])

        queue = queue[1:] + [0]
        queue[throw[b]-1] = b


    for i in range(num_balls):
        p = throw[i]

        dt = t - t_start[i]
        nx = vx[p] * dt if hand[i] == 0 else dist - vx[p] * dt
        ny = vy[p] * dt - 0.5 * g * dt * dt

        xs[i].append(nx)
        ys[i].append(ny)


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

    ## for each frame, update the data stored on each artist.
    #x = t[:frame]
    #y = z[:frame]
    ## update the scatter plot:
    #data = np.stack([x, y]).T
    #scat.set_offsets(data)
    ## update the line plot:
    #line2.set_xdata(t[:frame])
    #line2.set_ydata(z2[:frame])
    #return (scat, line2)


ani = animation.FuncAnimation(fig=fig, func=update, frames=len(ts), interval=1/fps)
plt.show()
