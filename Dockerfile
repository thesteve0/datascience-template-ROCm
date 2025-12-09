# ROCm PyTorch ML Development Container
# Base: Official AMD ROCm PyTorch image (Ubuntu 24.04)
FROM rocm/pytorch:rocm7.1_ubuntu24.04_py3.13_pytorch_release_2.9.1

# Workaround for Ubuntu 24.04 having pre-existing ubuntu user at UID 1000
# This prevents common-utils from creating users at UID 1001
# See: https://github.com/devcontainers/images/issues/1056
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu

# The common-utils feature will now be able to create the user with the specified UID