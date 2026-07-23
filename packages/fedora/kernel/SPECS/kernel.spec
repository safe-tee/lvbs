
%global _enable_debug_package 0
%global debug_package %{nil}

Name:           kernel
Version:        6.19.6
Release:        1%{?dist}
Summary:        Custom Linux kernel build

License:        GPLv2
URL:            https://www.kernel.org/
Source0:        linux-%{version}.tar.xz

BuildRequires:  bc
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  ncurses-devel
BuildRequires:  openssl
BuildRequires:  openssl-devel
BuildRequires:  elfutils-libelf-devel
BuildRequires:  bison
BuildRequires:  flex
BuildRequires:  perl

ExclusiveArch:  x86_64

%description
A simple custom Linux kernel RPM.
This spec is intentionally minimal and suitable for development,
testing, or CI builds.

%prep
%autosetup -n linux-%{version}

%build
# Use default config
make olddefconfig

# Build kernel and modules
make %{?_smp_mflags}

%install
rm -rf %{buildroot}

# Install modules
make INSTALL_MOD_PATH=%{buildroot} modules_install

# Install kernel image
mkdir -p %{buildroot}/boot
install -m 644 arch/x86/boot/bzImage \
    %{buildroot}/boot/vmlinuz-%{version}-simple

%files
/boot/vmlinuz-%{version}-simple
/lib/modules/%{version}*

%changelog
* Thu Mar 05 2026 Sriram Nambakam <snambakam@local>
- Initial simple kernel RPM for 16.9.6
