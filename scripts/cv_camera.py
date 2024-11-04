import cv2
import numpy as np

# Start capturing video from the default camera
cap = cv2.VideoCapture(0)

# Define the criteria for K-means
criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)

# Number of clusters (K)
K = 3


def distance(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def kmeans_cluster(k, points, offline=False):
    # # Apply K-means clustering to the filtered points
    #_, labels, centers = cv2.kmeans(points, K, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)
    #return centers  # Return the centroids of the clusters

    # init means and data to random values
    # use real data in your code
    means = points[:k]
    means = [means[i] for i in range(means.shape[0])]
    param = 0.01 # bigger numbers make the means change faster
    # must be between 0 and 1

    # online K-means (maybe doesn't work)
    for it in range(30):
        if offline:
            groups = [ [] for _ in range(k) ]
        for p in points:
            errors = [distance(p, c) for c in means]
            closest = np.argmin(errors)
            if offline:
                groups[closest].append(p)
            else:
                means[closest] = means[closest] * (1-param) + p * (param)
        if offline:
            means = [ np.mean(np.array(g), axis=0) for g in groups ]

    return means


def criteria_mask(pixels):
    #threshold = 200
    
    # Condition to check if a pixel is predominantly green
    #return (pixels[:, 1] > green_threshold) & (pixels[:, 1] > pixels[:, 0]) & (pixels[:, 1] > pixels[:, 2])

    # BGR
    return (pixels[:,:,0] < 100) & (pixels[:,:,1] < 100) & (pixels[:,:,2] > 150)


while True:
    # Capture a frame from the camera
    ret, frame = cap.read()
    
    # Check if frame was captured successfully
    if not ret:
        print("Failed to grab frame")
        break

    # Reshape the frame to a 2D array of pixels
    pixels = frame.reshape((-1, 3))
    pixels = np.float32(pixels)



    ## Raw image
    #cv2.imshow('raw', frame)


    
    ## Apply K-means clustering
    #ret, labels, centers = cv2.kmeans(pixels, K, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)

    ## Convert back to 8-bit values and create segmented image
    #centers = np.uint8(centers)
    #segmented_image = centers[labels.flatten()]
    #segmented_image = segmented_image.reshape(frame.shape)

    ## Display the segmented image
    #cv2.imshow('Segmented Image', segmented_image)




    points = np.column_stack(np.where(criteria_mask(frame) > 0))  # (y, x) coordinates
    if len(points) > 100:
        points = points[(points[:, 0] % 4 == 0) & (points[:, 1] % 4 == 0)]

    # If there are points after filtering, apply K-means
    #if len(points) > 0:
    if len(points) > K:
        centroids = kmeans_cluster(K, points)
        # Draw crosshairs at each centroid on the original frame
        for centroid in centroids:
            y, x = int(centroid[0]), int(centroid[1])
            cv2.drawMarker(frame, (x, y), (0, 0, 255), markerType=cv2.MARKER_CROSS, thickness=2)


    # Display the frame with crosshairs
    for y, x in points:
        frame[y, x] = (0, 255, 0)
    cv2.imshow('Frame with Crosshairs', frame)



    # Break the loop if 'q' is pressed
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# Release the camera and close windows
cap.release()
cv2.destroyAllWindows()
