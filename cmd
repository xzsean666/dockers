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

sudo -E ./publish-dockerhub.sh \
--context rclone-sync \
--file Dockerfile \
--image xzsean/rclone-sync \
--tag 0.1.0 \
--description "rclone bucket sync and archive runner"