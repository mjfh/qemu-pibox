# Expert example configuration file. This needs to go into the root folder
# of the <qemu-pibox> package (parallel to the "pibox.sh" tool.)

### Refer to a config file residing in another folder "custom-config-folder"
### parallel to the <qemu-pibox> package root folder.
. $prefix/../custom-config-folder/custom-config.sh

### In the "custom-config-folder" there is a file "custom-config.sh"
### with contents as follows.
#
# # Set prefix for this location relativ from the <qemu-pibox> package folder.
# config_prefix=$prefix/../custom-config-folder
#
# # Choose a place with enough disk space.
# PIBOX_CACHE=/qemu/cache
#
# # Some local file overwrites.
# ETC_HOSTS=$config_prefix/conf/hosts
# ETC_IFTAB=$config_prefix/conf/iftab
# ETC_WIFITAB=$config_prefix/conf/wifitab

# End
