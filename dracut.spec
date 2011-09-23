# Variables must be defined
%define with_switch_root	1
%define with_nbd		1

# switchroot provided by util-linux-ng in F-12+
%if 0%{?fedora} > 11 || 0%{?rhel} >= 6
%define with_switch_root 0
%endif
# nbd in Fedora only
%if 0%{?rhel} >= 6
%define with_nbd 0
%endif

Name: dracut
Version: 004
Release: 1%{?dist}
Summary: Initramfs generator using udev
Group: System Environment/Base		
License: GPLv2+	
URL: http://apps.sourceforge.net/trac/dracut/wiki

Source0: http://www.kernel.org/pub/linux/utils/boot/dracut/dracut-%{version}.tar.bz2

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%if 0%{?fedora} > 12 || 0%{?rhel} >= 6
# no "provides", because dracut does not offer
# all functionality of the obsoleted packages
Obsoletes: mkinitrd <= 6.0.93
Obsoletes: mkinitrd-devel <= 6.0.93
Obsoletes: nash <= 6.0.93
Obsoletes: libbdevid-python <= 6.0.93
%endif

Requires: bash
Requires: bzip2
Requires: coreutils
Requires: cpio
Requires: dash
Requires: filesystem >= 2.1.0
Requires: findutils
Requires: grep
Requires: gzip
Requires: initscripts >= 8.63-1
Requires: kbd
Requires: mktemp >= 1.5-5
Requires: module-init-tools >= 3.7-9
Requires: mount
Requires: plymouth >= 0.8.0-0.2009.29.09.19.1
Requires: plymouth-scripts
Requires: sed
Requires: tar
Requires: udev
Requires: util-linux-ng >= 2.16
Requires: which

%if ! 0%{?with_switch_root}
Requires: util-linux-ng >= 2.16
BuildArch: noarch
%endif

BuildRequires: docbook-style-xsl docbook-dtds libxslt

%description
dracut is a new, event-driven initramfs infrastructure based around udev.

%package network
Summary: Dracut modules to build a dracut initramfs with network support
Requires: %{name} = %{version}-%{release}
Requires: dhclient rpcbind nfs-utils 
Requires: iscsi-initiator-utils
%if %{with_nbd}
Requires: nbd
%endif
Requires: net-tools iproute
Requires: bridge-utils

%description network
This package requires everything which is needed to build a generic
all purpose initramfs with network support with dracut.

%package fips
Summary: Dracut modules to build a dracut initramfs with an integrity check
Requires: %{name} = %{version}-%{release}
Requires: hmaccalc fipscheck
%if 0%{?rhel} > 5
# For Alpha 3, we want nss instead of nss-softokn
Requires: nss
%else
Requires: nss-softokn
%endif
Requires: nss-softokn-freebl

%description fips
This package requires everything which is needed to build an
all purpose initramfs with dracut, which does an integrity check.

%package fips-aesni
Summary: Dracut modules to build a dracut initramfs with an integrity check with aesni-intel
Requires: %{name}-fips = %{version}-%{release}

%description fips-aesni
This package requires everything which is needed to build an
all purpose initramfs with dracut, which does an integrity check 
and adds the aesni-intel kernel module.

%package caps
Summary: Dracut modules to build a dracut initramfs which drops capabilities
Requires: %{name} = %{version}-%{release}
Requires: libcap

%description caps
This package requires everything which is needed to build an
all purpose initramfs with dracut, which drops capabilities.

%package generic
Summary: Metapackage to build a generic initramfs with dracut
Requires: %{name} = %{version}-%{release}
Requires: %{name}-network = %{version}-%{release}

%description generic
This package requires everything which is needed to build a generic
all purpose initramfs with dracut.


%package kernel
Summary: Metapackage to build generic initramfs with dracut with only kernel modules
Requires: %{name} = %{version}-%{release}

%description kernel
This package requires everything which is needed to build a initramfs with all
kernel modules and firmware files needed by dracut modules.

%package tools
Summary: Dracut tools to build the local initramfs
Requires: %{name} = %{version}-%{release}
Requires: coreutils cryptsetup-luks device-mapper
Requires: diffutils dmraid findutils gawk grep lvm2
Requires: module-init-tools sed
Requires: cpio gzip

%description tools
This package contains tools to assemble the local initrd and host configuration.

%prep
%setup -q -n %{name}-%{version}

chmod 0755 modules.d/*/check
# make rpmlint happy
chmod 0755 modules.d/*/install
chmod 0755 modules.d/*/installkernel
chmod 0755 modules.d/*/*.sh

%build
make WITH_SWITCH_ROOT=0%{?with_switch_root}

%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT sbindir=/sbin \
     sysconfdir=/etc mandir=%{_mandir} WITH_SWITCH_ROOT=0%{?with_switch_root}

echo %{name}-%{version}-%{release} > $RPM_BUILD_ROOT/%{_datadir}/dracut/modules.d/10rpmversion/dracut-version
rm $RPM_BUILD_ROOT/%{_datadir}/dracut/modules.d/01fips/check
rm $RPM_BUILD_ROOT/%{_datadir}/dracut/modules.d/02fips-aesni/check

mkdir -p $RPM_BUILD_ROOT/boot/dracut
mkdir -p $RPM_BUILD_ROOT/var/lib/dracut/overlay
mkdir -p $RPM_BUILD_ROOT%{_localstatedir}/log
touch $RPM_BUILD_ROOT%{_localstatedir}/log/dracut.log

%if 0%{?fedora} <= 12 && 0%{?rhel} < 6
rm $RPM_BUILD_ROOT/sbin/mkinitrd
rm $RPM_BUILD_ROOT/sbin/lsinitrd
%endif

mkdir -p $RPM_BUILD_ROOT/etc/logrotate.d
install -m 0644 dracut.logrotate $RPM_BUILD_ROOT/etc/logrotate.d/dracut

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,0755)
%doc README HACKING TODO COPYING AUTHORS NEWS dracut-rhel6.html
/sbin/dracut
%if 0%{?with_switch_root}
/sbin/switch_root
%endif
%if 0%{?fedora} > 12 || 0%{?rhel} >= 6
/sbin/mkinitrd
/sbin/lsinitrd
%endif
%dir %{_datadir}/dracut
%{_datadir}/dracut/dracut-functions
%config(noreplace) /etc/dracut.conf
%dir /etc/dracut.conf.d
%config(noreplace) /etc/logrotate.d/dracut
%{_mandir}/man8/dracut.8*
%{_mandir}/man5/dracut.conf.5*
%{_datadir}/dracut/modules.d/00dash
%{_datadir}/dracut/modules.d/10redhat-i18n
%{_datadir}/dracut/modules.d/10rpmversion
%{_datadir}/dracut/modules.d/50plymouth
%{_datadir}/dracut/modules.d/60xen
%{_datadir}/dracut/modules.d/90btrfs
%{_datadir}/dracut/modules.d/90crypt
%{_datadir}/dracut/modules.d/90dm
%{_datadir}/dracut/modules.d/90dmraid
%{_datadir}/dracut/modules.d/90dmsquash-live
%{_datadir}/dracut/modules.d/90kernel-modules
%{_datadir}/dracut/modules.d/90lvm
%{_datadir}/dracut/modules.d/90mdraid
%{_datadir}/dracut/modules.d/90multipath
%{_datadir}/dracut/modules.d/95debug
%{_datadir}/dracut/modules.d/95fstab-sys
%{_datadir}/dracut/modules.d/95resume
%{_datadir}/dracut/modules.d/95rootfs-block
%{_datadir}/dracut/modules.d/95dasd
%{_datadir}/dracut/modules.d/95dasd_mod
%{_datadir}/dracut/modules.d/95zfcp
%{_datadir}/dracut/modules.d/95znet
%{_datadir}/dracut/modules.d/95terminfo
%{_datadir}/dracut/modules.d/95udev-rules
%{_datadir}/dracut/modules.d/95uswsusp
%{_datadir}/dracut/modules.d/96insmodpost
%{_datadir}/dracut/modules.d/97biosdevname
%{_datadir}/dracut/modules.d/98syslog
%{_datadir}/dracut/modules.d/99base
%attr(0644,root,root) %ghost %config(missingok,noreplace) %{_localstatedir}/log/dracut.log

%files network
%defattr(-,root,root,0755)
%doc README HACKING TODO COPYING AUTHORS NEWS
%{_datadir}/dracut/modules.d/40network
%{_datadir}/dracut/modules.d/95fcoe
%{_datadir}/dracut/modules.d/95iscsi
%{_datadir}/dracut/modules.d/95nbd
%{_datadir}/dracut/modules.d/95nfs
%{_datadir}/dracut/modules.d/45ifcfg

%files fips
%defattr(-,root,root,0755)
%doc COPYING
%{_datadir}/dracut/modules.d/01fips

%files fips-aesni
%defattr(-,root,root,0755)
%doc COPYING
%{_datadir}/dracut/modules.d/02fips-aesni

%files caps
%defattr(-,root,root,0755)
%doc COPYING
%{_datadir}/dracut/modules.d/02caps

%files kernel 
%defattr(-,root,root,0755)
%doc README.kernel

%files generic
%defattr(-,root,root,0755)
%doc README.generic

%files tools 
%defattr(-,root,root,0755)
%doc COPYING NEWS
%{_mandir}/man8/dracut-gencmdline.8*
%{_mandir}/man8/dracut-catimages.8*
/sbin/dracut-gencmdline
/sbin/dracut-catimages
%dir /boot/dracut
%dir /var/lib/dracut
%dir /var/lib/dracut/overlay
 
%changelog
