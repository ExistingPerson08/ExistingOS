#!/bin/bash

set -ouex pipefail

### Install packages

rm -f /root/.bash_logout /root/.bash_profile /root/.bashrc

dnf5 install -y @workstation-product-environment --exclude=rootfiles

systemctl set-default graphical.target
systemctl enable gdm
systemctl enable NetworkManager

# Funtion to echo colored text
color_echo() {
    local color="$1"
    local text="$2"
    case "$color" in
        "red")     echo -e "\033[0;31m$text\033[0m" ;;
        "green")   echo -e "\033[0;32m$text\033[0m" ;;
        "yellow")  echo -e "\033[1;33m$text\033[0m" ;;
        "blue")    echo -e "\033[0;34m$text\033[0m" ;;
        *)         echo "$text" ;;
    esac
}

# Set variables
ACTUAL_USER=$SUDO_USER
ACTUAL_HOME=$(eval echo ~$SUDO_USER)
LOG_FILE="/var/log/fedora_things_to_do.log"
INITIAL_DIR=$(pwd)

# Function to generate timestamps
get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to log messages
log_message() {
    local message="$1"
    echo "$(get_timestamp) - $message" | tee -a "$LOG_FILE"
}

# Function to handle errors
handle_error() {
    local exit_code=$?
    local message="$1"
    if [ $exit_code -ne 0 ]; then
        color_echo "red" "ERROR: $message"
        exit $exit_code
    fi
}

# Function to prompt for reboot
prompt_reboot() {
    sudo  bash -c 'read -p "It is time to reboot the machine. Would you like to do it now? (y/n): " choice; [[ $choice == [yY] ]]'
    if [ $? -eq 0 ]; then
        color_echo "green" "Rebooting..."
        reboot
    else
        color_echo "red" "Reboot canceled."
    fi
}

# Function to backup configuration files
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "$file.bak"
        handle_error "Failed to backup $file"
        color_echo "green" "Backed up $file"
    fi
}

# System Upgrade
color_echo "blue" "Performing system upgrade... This may take a while..."
dnf5 upgrade -y


# System Configuration
# Replace Fedora Flatpak Repo with Flathub for better package management and apps stability
color_echo "yellow" "Replacing Fedora Flatpak Repo with Flathub..."
dnf5 install -y flatpak
flatpak remote-delete fedora --force || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak repair
flatpak update

# Enable RPM Fusion repositories to access additional software packages and codecs
color_echo "yellow" "Enabling RPM Fusion repositories..."
dnf5 install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf5 install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf5 update @core -y

# Install multimedia codecs to enhance multimedia capabilities
color_echo "yellow" "Installing multimedia codecs..."
dnf5 swap ffmpeg-free ffmpeg --allowerasing -y
dnf5 update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y
dnf5 update @sound-and-video -y

# Install Hardware Accelerated Codecs for Intel integrated GPUs. This improves video playback and encoding performance on systems with Intel graphics.
color_echo "yellow" "Installing Intel Hardware Accelerated Codecs..."
dnf5 -y install intel-media-driver

# Install Hardware Accelerated Codecs for AMD GPUs. This improves video playback and encoding performance on systems with AMD graphics.
color_echo "yellow" "Installing AMD Hardware Accelerated Codecs..."
dnf5 swap mesa-va-drivers mesa-va-drivers-freeworld -y
dnf5 swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld -y

# Install virtualization tools to enable virtual machines and containerization
color_echo "yellow" "Installing virtualization tools..."
dnf5 install -y @virtualization


# App Installation
# Install essential applications
color_echo "yellow" "Installing essential applications..."
dnf5 install -y htop rsync fastfetch unzip unrar git wget curl gnome-tweaks syncthing
color_echo "green" "Essential applications installed successfully."

# Install Internet & Communication applications
color_echo "yellow" "Installing Tor..."
dnf5 install -y tor
sleep 5
systemctl enable --now tor
flatpak install -y flathub org.torproject.torbrowser-launcher
color_echo "green" "Tor installed successfully."

# Install Office Productivity applications
color_echo "yellow" "Installing LibreOffice..."
dnf5 remove -y libreoffice*
flatpak install -y flathub org.libreoffice.LibreOffice
flatpak install -y --reinstall org.freedesktop.Platform.Locale/x86_64/24.08
flatpak install -y --reinstall org.libreoffice.LibreOffice.Locale
color_echo "green" "LibreOffice installed successfully."
color_echo "yellow" "Installing OnlyOffice..."
flatpak install -y flathub org.onlyoffice.desktopeditors
color_echo "green" "OnlyOffice installed successfully."

# Install Coding and DevOps applications
color_echo "yellow" "Installing Visual Studio Code..."
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
dnf5 check-update
dnf5 install -y code
color_echo "green" "Visual Studio Code installed successfully."
color_echo "yellow" "Installing Docker..."
dnf5 remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine --noautoremove
dnf5 -y install dnf-plugins-core
if command -v dnf4 &>/dev/null; then
  dnf4 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
else
  dnf5 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
fi
dnf5 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
systemctl enable --now containerd
groupadd docker
rm -rf $ACTUAL_HOME/.docker
echo "Docker installed successfully. Please log out and back in for the group changes to take effect."
color_echo "green" "Docker installed successfully."
# Note: Docker group changes will take effect after logging out and back in
color_echo "yellow" "Installing Podman..."
dnf5 install -y podman
color_echo "green" "Podman installed successfully."
color_echo "yellow" "Installing VeraCrypt..."
wget https://launchpad.net/veracrypt/trunk/1.26.20/+download/veracrypt-1.26.20-Fedora-40-x86_64.rpm
dnf5 install -y ./veracrypt-1.26.20-Fedora-40-x86_64.rpm
rm -f ./veracrypt-1.26.20-Fedora-40-x86_64.rpm
color_echo "green" "VeraCrypt installed successfully."
color_echo "yellow" "Installing Zsh and Oh My Zsh..."
dnf5 install -y zsh
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$ACTUAL_HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-$ACTUAL_HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-$ACTUAL_HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$ACTUAL_HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
sed -i 's/plugins=(git)/plugins=(dnf5 aliases genpass git zsh-autosuggestions zsh-autocomplete zsh-history-substring-search z zsh-syntax-highlighting)/' $ACTUAL_HOME/.zshrc
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="jonathan"/' $ACTUAL_HOME/.zshrc
EOF
color_echo "green" "Zsh and Oh My Zsh installed successfully."

# Install Gaming & Emulation applications
color_echo "yellow" "Installing Steam..."
dnf5 install -y steam
color_echo "green" "Steam installed successfully."
color_echo "yellow" "Installing Lutris..."
dnf5 install -y lutris
color_echo "green" "Lutris installed successfully."

# Install Remote Networking applications
color_echo "yellow" "Installing Tailscale..."
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 install tailscale -y
systemctl enable --now tailscaled
color_echo "green" "Tailscale installed successfully."


# Customization
# Install Microsoft Windows fonts (windows)
color_echo "yellow" "Installing Microsoft Fonts (windows)..."
dnf5 install -y wget cabextract xorg-x11-font-utils fontconfig
wget -O /tmp/winfonts.zip https://mktr.sbs/fonts
mkdir -p $ACTUAL_HOME/.local/share/fonts/windows
unzip /tmp/winfonts.zip -d $ACTUAL_HOME/.local/share/fonts/windows
rm -f /tmp/winfonts.zip
fc-cache -fv
color_echo "green" "Microsoft Fonts (windows) installed successfully."

# Install Google fonts collection
color_echo "yellow" "Installing Google Fonts..."
wget -O /tmp/google-fonts.zip https://github.com/google/fonts/archive/main.zip
mkdir -p $ACTUAL_HOME/.local/share/fonts/google
unzip /tmp/google-fonts.zip -d $ACTUAL_HOME/.local/share/fonts/google
rm -f /tmp/google-fonts.zip
fc-cache -fv
color_echo "green" "Google Fonts installed successfully."

# A flat colorful design icon theme for linux desktops
color_echo "yellow" "Installing Papirus Icon Theme..."
dnf5 install -y papirus-icon-theme
sudo  gsettings set org.gnome.desktop.interface icon-theme "Papirus"
color_echo "green" "Papirus Icon Theme installed successfully."

# A flat colorful design icon theme for linux desktops
color_echo "yellow" "Installing Numix Circle Icon Theme..."
dnf5 install -y numix-circle-icon-theme
sudo  gsettings set org.gnome.desktop.interface icon-theme "Numix-Circle"
color_echo "green" "Numix Circle Icon Theme installed successfully."

# Before finishing, ensure we're in a safe directory
cd /tmp || cd $ACTUAL_HOME || cd /
