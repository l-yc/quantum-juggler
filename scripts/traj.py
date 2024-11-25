import matplotlib.pyplot as plt
import numpy as np

# Parameters for the parabolic trajectory
v0 = 20  # initial velocity (m/s)
theta = 45  # launch angle (degrees)
g = 9.81  # acceleration due to gravity (m/s^2)

# Convert angle to radians
theta_rad = np.radians(theta)

# Time of flight and range calculation
time_of_flight = 2 * v0 * np.sin(theta_rad) / g
t = np.linspace(0, time_of_flight, num=100)  # time points

# Calculate x and y coordinates
x = v0 * np.cos(theta_rad) * t
y = v0 * np.sin(theta_rad) * t - 0.5 * g * t**2

# Mid-point of the trajectory
midpoint_index = len(t) // 2
mid_x, mid_y = x[midpoint_index], y[midpoint_index]

# Endpoint of the trajectory
end_x, end_y = x[-1], y[-1]

# Plotting
plt.figure(figsize=(10, 5))
plt.plot(x, y, label='Parabolic Trajectory')
plt.scatter(0, 0, color='blue', s=100, label='Left Hand')
plt.scatter(mid_x, mid_y, color='pink', s=100, label='Ball')
plt.scatter(end_x, end_y, color='cyan', s=100, label='Right Hand')

# Label with the kinematic equations for a parabola
equation_text = r"$h = v_y t - \frac{1}{2}g t^2$"
plt.text(0.05 * max(x), 0.8 * max(y), equation_text, fontsize=12, color='purple')
equation_text = r"$d = v_x t$"
plt.text(0.05 * max(x), 0.7 * max(y), equation_text, fontsize=12, color='purple')
equation_text = r"$\Delta d$ is from camera, $\Delta t$ is from ADC"
plt.text(0.2 * max(x), 0.4 * max(y), equation_text, fontsize=12, color='purple')

# Labels and title
plt.xlabel("Distance, d (m)")
plt.ylabel("Height, h (m)")
plt.title("Parabolic Ball Trajectory")
plt.legend()
plt.grid(False)
plt.show()
