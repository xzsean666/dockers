sudo ./publish-dockerhub.sh \
--context rclone-sync \
--file Dockerfile \
--image xzsean/rclone-sync \
--tag 0.1.0

sudo ./publish-dockerhub.sh \
--context rclone-sync \
--file Dockerfile \
--image xzsean/rclone-sync \
--tag 0.1.0 \
--platforms linux/amd64