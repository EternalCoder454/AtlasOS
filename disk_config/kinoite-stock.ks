# Unattended install of stock Fedora Kinoite 44 from the ISO in ~/VMs, used by
# `just mem` as the baseline. The payload line is the ISO's own default
# (usr/share/anaconda/interactive-defaults.ks inside images/install.img); the
# rest answers the questions the interactive installer would ask, and puts back
# two things a graphical install does by itself: boot to the login screen
# (a text-mode install would leave the default at multi-user.target) and
# Fedora's "rhgb quiet" (the Plymouth splash), which --append would replace.
# @PASSWORD_HASH@ is filled in by scripts/vm.sh from build/vm-password.

text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --activate
firewall --use-system-defaults

zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --noswap
bootloader --append="rhgb quiet console=ttyS0,115200 console=tty0 plymouth.ignore-serial-consoles"
xconfig --startxonboot

ostreesetup --nogpg --osname=fedora --remote=fedora --url=file:///ostree/repo --ref=fedora/44/x86_64/kinoite

rootpw --lock
user --name=atlas --groups=wheel --iscrypted --password=@PASSWORD_HASH@

poweroff

%post --erroronfail
cp /etc/skel/.bash* /root
%end
