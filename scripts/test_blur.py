import cv2

image = cv2.imread("images/test_image.jpg")

for i in range(3):
    image = cv2.GaussianBlur(image, (3, 3), 0)
    cv2.imwrite(f"images/blurred_image_3_{i}.jpg", image)

for i in range(3):
    image = cv2.GaussianBlur(image, (5, 5), 0)
    cv2.imwrite(f"images/blurred_image_5_{i}.jpg", image)
