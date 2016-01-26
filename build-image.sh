#!/bin/bash -x
### Build a docker image for ubuntu armhf.

set -e

### settings
arch=armhf
suite=trusty
suite_number=14.04
chroot_dir="/var/chroot/ubuntu_armhf_$suite"
docker_image="osrf/ubuntu_armhf:$suite"

### make sure that the required tools are installed
#apt-get install -y docker.io qemu-arm-static

# fetch and unpack base image
ARCHIVE_NAME=ubuntu-core-$suite_number-core-armhf.tar
BASE_IMAGE_URL=http://cdimage.ubuntu.com/ubuntu-core/releases/$suite/release/$ARCHIVE_NAME.gz
mkdir -p $chroot_dir
if [ ! -e /tmp/$ARCHIVE_NAME.gz ]; then
  curl $BASE_IMAGE_URL -o /tmp/$ARCHIVE_NAME.gz
fi
tar -xf /tmp/$ARCHIVE_NAME.gz -C $chroot_dir

# a few minor docker-specific tweaks
# see https://github.com/docker/docker/blob/master/contrib/mkimage/debootstrap

# prevent init scripts from running during install/update
echo '#!/bin/sh' > $chroot_dir/usr/sbin/policy-rc.d
echo 'exit 101' >> $chroot_dir/usr/sbin/policy-rc.d
chmod +x $chroot_dir/usr/sbin/policy-rc.d

# force dpkg not to call sync() after package extraction (speeding up installs)
echo 'force-unsafe-io' > $chroot_dir/etc/dpkg/dpkg.cfg.d/docker-apt-speedup

# _keep_ us lean by effectively running "apt-get clean" after every install
echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' > $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean
echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' >> $chroot_dir/etc/apt/apt.conf.d/docker-clean

# remove apt-cache translations for fast "apt-get update"
echo 'Acquire::Languages "none";' > $chroot_dir/etc/apt/apt.conf.d/docker-no-languages

# store Apt lists files gzipped on-disk for smaller size
echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > $chroot_dir/etc/apt/apt.conf.d/docker-gzip-indexes

# add qemu to base image
cp /usr/bin/qemu-arm-static $chroot_dir/usr/bin/

### create a tar archive from the chroot directory
tar cfz ubuntu_armhf_$suite.tgz -C $chroot_dir .

### import this tar archive into a docker image:
cat ubuntu_armhf_$suite.tgz | docker import - $docker_image

# Update packages
# FIXME Replace udev hold as soon as it does correctly upgrade on qemu
UPDATE_SCRIPT="dpkg-divert --local --rename --add /sbin/initctl && \
               ln -s /bin/true /sbin/initctl && \
               echo 'udev hold' | dpkg --set-selections && \
               sed -i -e 's/# \(.*universe\)$/\1/' /etc/apt/sources.list && \
               export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get -y upgrade"
CID=`sudo docker run -d $docker_image sh -c "$UPDATE_SCRIPT"`
sudo docker attach $CID
sudo docker commit $CID $docker_image
sudo docker rm $CID

# ### cleanup
rm ubuntu_armhf_$suite.tgz
rm -rf $chroot_dir

### push image to Docker Hub
echo "Test the image $docker_image and push it to upstream with 'docker push $docker_image'"
